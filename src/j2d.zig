const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const unicode = std.unicode;
const sdl = @import("sdl");
const jok = @import("jok.zig");
const imgui = jok.imgui;
const zmath = jok.zmath;
const zmesh = jok.zmesh;

const dc = @import("j2d/command.zig");
const Atlas = @import("font/Atlas.zig");
pub const Sprite = @import("j2d/Sprite.zig");
pub const SpriteSheet = @import("j2d/SpriteSheet.zig");
pub const ParticleSystem = @import("j2d/ParticleSystem.zig");
pub const AnimationSystem = @import("j2d/AnimationSystem.zig");
pub const Scene = @import("j2d/Scene.zig");
pub const Vector = @import("j2d/Vector.zig");

pub const Error = error{
    PathNotFinished,
};

pub const TransformOption = struct {
    scale: sdl.PointF = .{ .x = 1, .y = 1 },
    anchor: sdl.PointF = .{ .x = 0, .y = 0 },
    rotate_degree: f32 = 0,
    offset: sdl.PointF = .{ .x = 0, .y = 0 },

    pub fn getMatrix(self: TransformOption) zmath.Mat {
        return getTransformMatrix(
            self.scale,
            self.anchor,
            self.rotate_degree,
            self.offset,
        );
    }

    pub fn getNoScaleMatrix(self: TransformOption) zmath.Mat {
        return getTransformMatrix(
            .{ .x = 1, .y = 1 },
            self.anchor,
            self.rotate_degree,
            self.offset,
        );
    }
};

pub const DepthSortMethod = enum {
    none,
    back_to_forth,
    forth_to_back,
};

pub const BlendMethod = enum {
    blend,
    additive,
    overwrite,
};

pub const BeginOption = struct {
    trs: TransformOption = .{},
    depth_sort: DepthSortMethod = .none,
    blend_method: BlendMethod = .blend,
    antialiased: bool = true,
};

var arena: std.heap.ArenaAllocator = undefined;
var rd: sdl.Renderer = undefined;
var draw_list: imgui.DrawList = undefined;
var draw_commands: std.ArrayList(dc.DrawCmd) = undefined;
var trs: TransformOption = undefined;
var trs_m: zmath.Mat = undefined;
var trs_noscale_m: zmath.Mat = undefined;
var depth_sort: DepthSortMethod = undefined;
var blend_method: BlendMethod = undefined;
var all_tex: std.AutoHashMap(*sdl.c.SDL_Texture, bool) = undefined;

pub fn init(allocator: std.mem.Allocator, _rd: sdl.Renderer) !void {
    arena = std.heap.ArenaAllocator.init(allocator);
    rd = _rd;
    draw_list = imgui.createDrawList();
    draw_commands = std.ArrayList(dc.DrawCmd).init(allocator);
    all_tex = std.AutoHashMap(*sdl.c.SDL_Texture, bool).init(allocator);
}

pub fn deinit() void {
    arena.deinit();
    imgui.destroyDrawList(draw_list);
    draw_commands.deinit();
    all_tex.deinit();
}

pub fn begin(opt: BeginOption) !void {
    draw_list.reset();
    draw_list.pushClipRectFullScreen();
    draw_list.pushTextureId(imgui.io.getFontsTexId());
    draw_commands.clearRetainingCapacity();
    all_tex.clearRetainingCapacity();
    trs = opt.trs;
    trs_m = opt.trs.getMatrix();
    trs_noscale_m = opt.trs.getNoScaleMatrix();
    depth_sort = opt.depth_sort;
    blend_method = opt.blend_method;
    if (opt.antialiased) {
        draw_list.setDrawListFlags(.{
            .anti_aliased_lines = true,
            .anti_aliased_lines_use_tex = false,
            .anti_aliased_fill = true,
            .allow_vtx_offset = true,
        });
    }
}

pub fn end() !void {
    const S = struct {
        fn ascendCompare(_: ?*anyopaque, lhs: dc.DrawCmd, rhs: dc.DrawCmd) bool {
            return lhs.depth < rhs.depth;
        }
        fn descendCompare(_: ?*anyopaque, lhs: dc.DrawCmd, rhs: dc.DrawCmd) bool {
            return lhs.depth > rhs.depth;
        }
    };

    if (draw_commands.items.len == 0) return;

    switch (depth_sort) {
        .none => {},
        .back_to_forth => std.sort.sort(
            dc.DrawCmd,
            draw_commands.items,
            @as(?*anyopaque, null),
            S.descendCompare,
        ),
        .forth_to_back => std.sort.sort(
            dc.DrawCmd,
            draw_commands.items,
            @as(?*anyopaque, null),
            S.ascendCompare,
        ),
    }
    for (draw_commands.items) |dcmd| {
        switch (dcmd.cmd) {
            .image => |c| try all_tex.put(c.texture.ptr, true),
            .image_rounded => |c| try all_tex.put(c.texture.ptr, true),
            .quad_image => |c| try all_tex.put(c.texture.ptr, true),
            else => {},
        }
        try dcmd.render(draw_list);
    }
    const mode = switch (blend_method) {
        .blend => sdl.c.SDL_BLENDMODE_BLEND,
        .additive => sdl.c.SDL_BLENDMODE_ADD,
        .overwrite => sdl.c.SDL_BLENDMODE_NONE,
    };
    var it = all_tex.keyIterator();
    while (it.next()) |k| {
        _ = sdl.c.SDL_SetTextureBlendMode(k.*, @intCast(c_uint, mode));
    }
    try imgui.sdl.renderDrawList(rd, draw_list);
}

pub fn recycleMemory() void {
    imgui.clearMemory(draw_list);
    draw_commands.clearAndFree();
    all_tex.clearAndFree();
}

pub fn pushClipRect(rect: sdl.RectangleF, intersect_with_current: bool) void {
    draw_list.pushClipRect(.{
        .pmin = .{ rect.x, rect.y },
        .pmax = .{ rect.x + rect.width, rect.y + rect.height },
        .intersect_with_current = intersect_with_current,
    });
}

pub fn popClipRect() void {
    draw_list.popClipRect();
}

pub const AddLine = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    depth: f32 = 0.5,
};
pub fn addLine(p1: sdl.PointF, p2: sdl.PointF, color: sdl.Color, opt: AddLine) !void {
    try draw_commands.append(.{
        .cmd = .{
            .line = .{
                .p1 = transformPoint(p1, opt.trs),
                .p2 = transformPoint(p2, opt.trs),
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
            },
        },
        .depth = opt.depth,
    });
}

pub const AddRect = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    rounding: f32 = 0,
    depth: f32 = 0.5,
};
pub fn addRect(rect: sdl.RectangleF, color: sdl.Color, opt: AddRect) !void {
    const scale = getScale(opt.trs);
    const pmin = transformPoint(.{ .x = rect.x, .y = rect.y }, opt.trs);
    const pmax = sdl.PointF{
        .x = pmin.x + rect.width * scale.x,
        .y = pmin.y + rect.height * scale.y,
    };
    try draw_commands.append(.{
        .cmd = .{
            .rect = .{
                .pmin = pmin,
                .pmax = pmax,
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
                .rounding = opt.rounding,
            },
        },
        .depth = opt.depth,
    });
}

pub const FillRect = struct {
    trs: ?TransformOption = null,
    rounding: f32 = 0,
    depth: f32 = 0.5,
};
pub fn addRectFilled(rect: sdl.RectangleF, color: sdl.Color, opt: FillRect) !void {
    const scale = getScale(opt.trs);
    const pmin = transformPoint(.{ .x = rect.x, .y = rect.y }, opt.trs);
    const pmax = sdl.PointF{
        .x = pmin.x + rect.width * scale.x,
        .y = pmin.y + rect.height * scale.y,
    };
    try draw_commands.append(.{
        .cmd = .{
            .rect_fill = .{
                .pmin = pmin,
                .pmax = pmax,
                .color = imgui.sdl.convertColor(color),
                .rounding = opt.rounding,
            },
        },
        .depth = opt.depth,
    });
}

pub const FillRectMultiColor = struct {
    trs: ?TransformOption = null,
    depth: f32 = 0.5,
};
pub fn addRectFilledMultiColor(
    rect: sdl.RectangleF,
    color_top_left: sdl.Color,
    color_top_right: sdl.Color,
    color_bottom_right: sdl.Color,
    color_bottom_left: sdl.Color,
    opt: FillRectMultiColor,
) !void {
    const scale = getScale(opt.trs);
    const pmin = transformPoint(.{ .x = rect.x, .y = rect.y }, opt.trs);
    const pmax = sdl.PointF{
        .x = pmin.x + rect.width * scale.x,
        .y = pmin.y + rect.height * scale.y,
    };
    try draw_commands.append(.{
        .cmd = .{
            .rect_fill_multicolor = .{
                .pmin = pmin,
                .pmax = pmax,
                .color_ul = imgui.sdl.convertColor(color_top_left),
                .color_ur = imgui.sdl.convertColor(color_top_right),
                .color_br = imgui.sdl.convertColor(color_bottom_right),
                .color_bl = imgui.sdl.convertColor(color_bottom_left),
            },
        },
        .depth = opt.depth,
    });
}

pub const AddQuad = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    depth: f32 = 0.5,
};
pub fn addQuad(
    p1: sdl.PointF,
    p2: sdl.PointF,
    p3: sdl.PointF,
    p4: sdl.PointF,
    color: sdl.Color,
    opt: AddQuad,
) !void {
    try draw_commands.append(.{
        .cmd = .{
            .quad = .{
                .p1 = transformPoint(p1, opt.trs),
                .p2 = transformPoint(p2, opt.trs),
                .p3 = transformPoint(p3, opt.trs),
                .p4 = transformPoint(p4, opt.trs),
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
            },
        },
        .depth = opt.depth,
    });
}

pub const FillQuad = struct {
    trs: ?TransformOption = null,
    depth: f32 = 0.5,
};
pub fn addQuadFilled(
    p1: sdl.PointF,
    p2: sdl.PointF,
    p3: sdl.PointF,
    p4: sdl.PointF,
    color: sdl.Color,
    opt: FillQuad,
) !void {
    try draw_commands.append(.{
        .cmd = .{
            .quad_fill = .{
                .p1 = transformPoint(p1, opt.trs),
                .p2 = transformPoint(p2, opt.trs),
                .p3 = transformPoint(p3, opt.trs),
                .p4 = transformPoint(p4, opt.trs),
                .color = imgui.sdl.convertColor(color),
            },
        },
        .depth = opt.depth,
    });
}

pub const AddTriangle = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    depth: f32 = 0.5,
};
pub fn addTriangle(
    p1: sdl.PointF,
    p2: sdl.PointF,
    p3: sdl.PointF,
    color: sdl.Color,
    opt: AddTriangle,
) !void {
    try draw_commands.append(.{
        .cmd = .{
            .triangle = .{
                .p1 = transformPoint(p1, opt.trs),
                .p2 = transformPoint(p2, opt.trs),
                .p3 = transformPoint(p3, opt.trs),
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
            },
        },
        .depth = opt.depth,
    });
}

pub const FillTriangle = struct {
    trs: ?TransformOption = null,
    depth: f32 = 0.5,
};
pub fn addTriangleFilled(
    p1: sdl.PointF,
    p2: sdl.PointF,
    p3: sdl.PointF,
    color: sdl.Color,
    opt: FillTriangle,
) !void {
    try draw_commands.append(.{
        .cmd = .{
            .triangle_fill = .{
                .p1 = transformPoint(p1, opt.trs),
                .p2 = transformPoint(p2, opt.trs),
                .p3 = transformPoint(p3, opt.trs),
                .color = imgui.sdl.convertColor(color),
            },
        },
        .depth = opt.depth,
    });
}

pub const AddCircle = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    num_segments: u32 = 0,
    depth: f32 = 0.5,
};
pub fn addCircle(
    center: sdl.PointF,
    radius: f32,
    color: sdl.Color,
    opt: AddCircle,
) !void {
    const scale = getScale(opt.trs);
    try draw_commands.append(.{
        .cmd = .{
            .circle = .{
                .p = transformPoint(center, opt.trs),
                .radius = radius * scale.x,
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
                .num_segments = opt.num_segments,
            },
        },
        .depth = opt.depth,
    });
}

pub const FillCircle = struct {
    trs: ?TransformOption = null,
    num_segments: u32 = 0,
    depth: f32 = 0.5,
};
pub fn addCircleFilled(
    center: sdl.PointF,
    radius: f32,
    color: sdl.Color,
    opt: FillCircle,
) !void {
    const scale = getScale(opt.trs);
    try draw_commands.append(.{
        .cmd = .{
            .circle_fill = .{
                .p = transformPoint(center, opt.trs),
                .radius = radius * scale.x,
                .color = imgui.sdl.convertColor(color),
                .num_segments = opt.num_segments,
            },
        },
        .depth = opt.depth,
    });
}

pub const AddNgon = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    depth: f32 = 0.5,
};
pub fn addNgon(
    center: sdl.PointF,
    radius: f32,
    color: sdl.Color,
    num_segments: u32,
    opt: AddNgon,
) !void {
    const scale = getScale(opt.trs);
    try draw_commands.append(.{
        .cmd = .{
            .ngon = .{
                .p = transformPoint(center, opt.trs),
                .radius = radius * scale.x,
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
                .num_segments = num_segments,
            },
        },
        .depth = opt.depth,
    });
}

pub const FillNgon = struct {
    trs: ?TransformOption = null,
    depth: f32 = 0.5,
};
pub fn addNgonFilled(
    center: sdl.PointF,
    radius: f32,
    color: sdl.Color,
    num_segments: u32,
    opt: FillNgon,
) !void {
    const scale = getScale(opt.trs);
    try draw_commands.append(.{
        .cmd = .{
            .ngon_fill = .{
                .p = transformPoint(center, opt.trs),
                .radius = radius * scale.x,
                .color = imgui.sdl.convertColor(color),
                .num_segments = num_segments,
            },
        },
        .depth = opt.depth,
    });
}

pub const AddBezierCubic = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    num_segments: u32 = 0,
    depth: f32 = 0.5,
};
pub fn addBezierCubic(
    p1: sdl.PointF,
    p2: sdl.PointF,
    p3: sdl.PointF,
    p4: sdl.PointF,
    color: sdl.Color,
    opt: AddBezierCubic,
) !void {
    try draw_commands.append(.{
        .cmd = .{
            .bezier_cubic = .{
                .p1 = transformPoint(p1, opt.trs),
                .p2 = transformPoint(p2, opt.trs),
                .p3 = transformPoint(p3, opt.trs),
                .p4 = transformPoint(p4, opt.trs),
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
                .num_segments = opt.num_segments,
            },
        },
        .depth = opt.depth,
    });
}

pub const AddBezierQuadratic = struct {
    trs: ?TransformOption = null,
    thickness: f32 = 1.0,
    num_segments: u32 = 0,
    depth: f32 = 0.5,
};
pub fn addBezierQuadratic(
    p1: sdl.PointF,
    p2: sdl.PointF,
    p3: sdl.PointF,
    color: sdl.Color,
    opt: AddBezierQuadratic,
) !void {
    try draw_commands.append(.{
        .cmd = .{
            .bezier_quadratic = .{
                .p1 = transformPoint(p1, opt.trs),
                .p2 = transformPoint(p2, opt.trs),
                .p3 = transformPoint(p3, opt.trs),
                .color = imgui.sdl.convertColor(color),
                .thickness = opt.thickness,
                .num_segments = opt.num_segments,
            },
        },
        .depth = opt.depth,
    });
}

pub const AddImage = struct {
    trs: ?TransformOption = null,
    uv0: sdl.PointF = .{ .x = 0, .y = 0 },
    uv1: sdl.PointF = .{ .x = 1, .y = 1 },
    tint_color: sdl.Color = sdl.Color.white,
    scale: sdl.PointF = .{ .x = 1, .y = 1 },
    rotate_degree: f32 = 0,
    anchor_point: sdl.PointF = .{ .x = 0, .y = 0 },
    flip_h: bool = false,
    flip_v: bool = false,
    depth: f32 = 0.5,
};
pub fn addImage(texture: sdl.Texture, rect: sdl.RectangleF, opt: AddImage) !void {
    const scale = getScale(opt.trs);
    const pos = transformPoint(.{ .x = rect.x, .y = rect.y }, opt.trs);
    const sprite = Sprite{
        .width = rect.width,
        .height = rect.height,
        .uv0 = opt.uv0,
        .uv1 = opt.uv1,
        .tex = texture,
    };
    try sprite.render(&draw_commands, .{
        .pos = pos,
        .tint_color = opt.tint_color,
        .scale = .{ .x = scale.x * opt.scale.x, .y = scale.y * opt.scale.y },
        .rotate_degree = opt.rotate_degree,
        .anchor_point = opt.anchor_point,
        .flip_h = opt.flip_h,
        .flip_v = opt.flip_v,
        .depth = opt.depth,
    });
}

pub const AddImageRounded = struct {
    trs: ?TransformOption = null,
    uv0: sdl.PointF = .{ .x = 0, .y = 0 },
    uv1: sdl.PointF = .{ .x = 1, .y = 1 },
    tint_color: sdl.Color = sdl.Color.white,
    scale: sdl.PointF = .{ .x = 1, .y = 1 },
    flip_h: bool = false,
    flip_v: bool = false,
    rounding: f32 = 4,
    depth: f32 = 0.5,
};
pub fn addImageRounded(texture: sdl.Texture, rect: sdl.RectangleF, opt: AddImageRounded) !void {
    const scale = getScale(opt.trs);
    const pmin = transformPoint(.{ .x = rect.x, .y = rect.y }, opt.trs);
    const pmax = sdl.PointF{
        .x = pmin.x + rect.width * scale.x,
        .y = pmin.y + rect.height * scale.y,
    };
    var uv0 = opt.uv0;
    var uv1 = opt.uv1;
    if (opt.flip_h) std.mem.swap(f32, &uv0.x, &uv1.x);
    if (opt.flip_v) std.mem.swap(f32, &uv0.y, &uv1.y);
    try draw_commands.append(.{
        .cmd = .{
            .image_rounded = .{
                .texture = texture,
                .pmin = pmin,
                .pmax = pmax,
                .uv0 = uv0,
                .uv1 = uv1,
                .rounding = opt.rounding,
                .tint_color = imgui.sdl.convertColor(opt.tint_color),
            },
        },
        .depth = opt.depth,
    });
}

// TODO global trs not taking effect
pub fn addScene(scene: *const Scene, opt: Scene.RenderOption) !void {
    try scene.render(&draw_commands, opt);
}

// TODO global trs not taking effect
pub fn addEffects(ps: *const ParticleSystem, opt: ParticleSystem.RenderOption) !void {
    for (ps.effects.items) |eff| {
        try eff.render(
            &draw_commands,
            opt,
        );
    }
}

pub const AddSprite = struct {
    pos: sdl.PointF,
    trs: ?TransformOption = null,
    tint_color: sdl.Color = sdl.Color.white,
    scale: sdl.PointF = .{ .x = 1, .y = 1 },
    rotate_degree: f32 = 0,
    anchor_point: sdl.PointF = .{ .x = 0, .y = 0 },
    flip_h: bool = false,
    flip_v: bool = false,
    depth: f32 = 0.5,
};
pub fn addSprite(sprite: Sprite, opt: AddSprite) !void {
    const scale = getScale(opt.trs);
    try sprite.render(&draw_commands, .{
        .pos = transformPoint(opt.pos, opt.trs),
        .tint_color = opt.tint_color,
        .scale = .{ .x = scale.x * opt.scale.x, .y = scale.y * opt.scale.y },
        .rotate_degree = opt.rotate_degree,
        .anchor_point = opt.anchor_point,
        .flip_h = opt.flip_h,
        .flip_v = opt.flip_v,
        .depth = opt.depth,
    });
}

pub const AddText = struct {
    atlas: Atlas,
    pos: sdl.PointF,
    trs: ?TransformOption = null,
    ypos_type: Atlas.YPosType = .top,
    tint_color: sdl.Color = sdl.Color.white,
    scale: sdl.PointF = .{ .x = 1, .y = 1 },
    rotate_degree: f32 = 0,
    anchor_point: sdl.PointF = .{ .x = 0, .y = 0 },
    depth: f32 = 0.5,
};
pub fn addText(opt: AddText, comptime fmt: []const u8, args: anytype) !void {
    const text = jok.imgui.format(fmt, args);
    if (text.len == 0) return;

    var pos = transformPoint(opt.pos, opt.trs);
    const scale = getScale(opt.trs);
    const angle = jok.utils.math.degreeToRadian(opt.rotate_degree);
    const mat = zmath.mul(
        zmath.mul(
            zmath.translation(-pos.x, -pos.y, 0),
            zmath.rotationZ(angle),
        ),
        zmath.translation(pos.x, pos.y, 0),
    );
    var i: u32 = 0;
    while (i < text.len) {
        const size = try unicode.utf8ByteSequenceLength(text[i]);
        const cp = @intCast(u32, try unicode.utf8Decode(text[i .. i + size]));
        if (opt.atlas.getVerticesOfCodePoint(pos, opt.ypos_type, sdl.Color.white, cp)) |cs| {
            const v = zmath.mul(
                zmath.f32x4(
                    cs.vs[0].position.x,
                    pos.y + (cs.vs[0].position.y - pos.y) * scale.y,
                    0,
                    1,
                ),
                mat,
            );
            const draw_pos = sdl.PointF{ .x = v[0], .y = v[1] };
            const sprite = Sprite{
                .width = cs.vs[1].position.x - cs.vs[0].position.x,
                .height = cs.vs[3].position.y - cs.vs[0].position.y,
                .uv0 = cs.vs[0].tex_coord,
                .uv1 = cs.vs[2].tex_coord,
                .tex = opt.atlas.tex,
            };
            try sprite.render(&draw_commands, .{
                .pos = draw_pos,
                .tint_color = opt.tint_color,
                .scale = .{ .x = scale.x * opt.scale.x, .y = scale.y * opt.scale.y },
                .rotate_degree = opt.rotate_degree,
                .anchor_point = opt.anchor_point,
                .depth = opt.depth,
            });
            pos.x += (cs.next_x - pos.x) * scale.x;
        }
        i += size;
    }
}

pub const AddPath = struct {
    depth: f32 = 0.5,
};
pub fn addPath(path: Path, opt: AddPath) !void {
    if (!path.finished) return error.PathNotFinished;
    var rpath = path.path;
    rpath.trs = trs;
    rpath.trs_m = trs_m;
    rpath.trs_noscale_m = trs_noscale_m;
    try draw_commands.append(.{
        .cmd = .{ .path = rpath },
        .depth = opt.depth,
    });
}

pub const Path = struct {
    path: dc.PathCmd,
    finished: bool = false,

    /// Begin definition of path
    pub const PathBegin = struct {
        trs: ?TransformOption = null,
    };
    pub fn begin(allocator: std.mem.Allocator, opt: PathBegin) Path {
        return .{
            .path = dc.PathCmd.init(allocator, opt.trs),
        };
    }

    /// End definition of path
    pub const PathEnd = struct {
        color: sdl.Color = sdl.Color.white,
        thickness: f32 = 1.0,
        closed: bool = false,
    };
    pub fn end(
        self: *Path,
        method: dc.PathCmd.DrawMethod,
        opt: PathEnd,
    ) void {
        self.path.draw_method = method;
        self.path.color = imgui.sdl.convertColor(opt.color);
        self.path.thickness = opt.thickness;
        self.path.closed = opt.closed;
        self.finished = true;
    }

    pub fn deinit(self: *Path) void {
        self.path.deinit();
        self.* = undefined;
    }

    pub fn reset(self: *Path, opt: PathBegin) void {
        self.path.cmds.clearRetainingCapacity();
        self.path.local_trs = opt.trs;
        self.finished = false;
    }

    pub fn lineTo(self: *Path, pos: sdl.PointF) !void {
        try self.path.cmds.append(.{ .line_to = .{ .p = pos } });
    }

    pub const ArcTo = struct {
        num_segments: u32 = 0,
    };
    pub fn arcTo(
        self: *Path,
        pos: sdl.PointF,
        radius: f32,
        degree_begin: f32,
        degree_end: f32,
        opt: ArcTo,
    ) !void {
        try self.path.cmds.append(.{
            .arc_to = .{
                .p = pos,
                .radius = radius,
                .amin = jok.utils.math.degreeToRadian(degree_begin),
                .amax = jok.utils.math.degreeToRadian(degree_end),
                .num_segments = opt.num_segments,
            },
        });
    }

    pub const BezierCurveTo = struct {
        num_segments: u32 = 0,
    };
    pub fn bezierCubicCurveTo(
        self: *Path,
        p2: sdl.PointF,
        p3: sdl.PointF,
        p4: sdl.PointF,
        opt: BezierCurveTo,
    ) !void {
        try self.path.cmds.append(.{
            .bezier_cubic_to = .{
                .p2 = p2,
                .p3 = p3,
                .p4 = p4,
                .num_segments = opt.num_segments,
            },
        });
    }
    pub fn bezierQuadraticCurveTo(
        self: *Path,
        p2: sdl.PointF,
        p3: sdl.PointF,
        opt: BezierCurveTo,
    ) !void {
        try self.path.cmds.append(.{
            .bezier_quadratic_to = .{
                .p2 = p2,
                .p3 = p3,
                .num_segments = opt.num_segments,
            },
        });
    }

    pub const Rect = struct {
        rounding: f32 = 0,
    };
    pub fn rect(
        self: *Path,
        r: sdl.RectangleF,
        opt: Rect,
    ) !void {
        const pmin = sdl.PointF{ .x = r.x, .y = r.y };
        const pmax = sdl.PointF{
            .x = pmin.x + r.width,
            .y = pmin.y + r.height,
        };
        try self.path.cmds.append(.{
            .rect = .{
                .pmin = pmin,
                .pmax = pmax,
                .rounding = opt.rounding,
            },
        });
    }
};

inline fn getTransformMatrix(scale: sdl.PointF, anchor: sdl.PointF, rotate_degree: f32, offset: sdl.PointF) zmath.Mat {
    const m1 = zmath.scaling(scale.x, scale.y, 0);
    const m2 = zmath.translation(-anchor.x, -anchor.y, 0);
    const m3 = zmath.rotationZ(jok.utils.math.degreeToRadian(rotate_degree));
    const m4 = zmath.translation(anchor.x, anchor.y, 0);
    const m5 = zmath.translation(offset.x, offset.y, 0);
    return zmath.mul(zmath.mul(zmath.mul(zmath.mul(m1, m2), m3), m4), m5);
}

inline fn transformPoint(point: sdl.PointF, local_trs: ?TransformOption) sdl.PointF {
    if (local_trs) |a| { // Merge two transformations
        const m1 = zmath.scaling(trs.scale.x * a.scale.x, trs.scale.y * a.scale.y, 0);
        const m2 = trs_noscale_m;
        const m1m2 = zmath.mul(m1, m2);
        const v1 = zmath.mul(zmath.f32x4(point.x, point.y, 0, 1), m1m2);
        const v2 = zmath.mul(zmath.f32x4(trs.anchor.x, trs.anchor.y, 0, 1), m1m2);

        const anchor_x = a.anchor.x + v2[0];
        const anchor_y = a.anchor.y + v2[1];
        const m3 = zmath.translation(-anchor_x, -anchor_y, 0);
        const m4 = zmath.rotationZ(jok.utils.math.degreeToRadian(a.rotate_degree));
        const m5 = zmath.translation(anchor_x, anchor_y, 0);
        const m6 = zmath.translation(a.offset.x, a.offset.y, 0);
        const v3 = zmath.mul(v1, zmath.mul(zmath.mul(zmath.mul(m3, m4), m5), m6));
        return sdl.PointF{ .x = v3[0], .y = v3[1] };
    } else { // Only global transformation
        const v = zmath.f32x4(point.x, point.y, 0, 1);
        const tv = zmath.mul(v, trs_m);
        return sdl.PointF{ .x = tv[0], .y = tv[1] };
    }
}

inline fn getScale(local_trs: ?TransformOption) sdl.PointF {
    if (local_trs) |a| {
        return .{
            .x = trs.scale.x * a.scale.x,
            .y = trs.scale.y * a.scale.y,
        };
    } else {
        return trs.scale;
    }
}
