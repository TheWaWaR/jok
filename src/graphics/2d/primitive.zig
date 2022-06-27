const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const sdl = @import("sdl");

var rd: ?Renderer = null;

/// Create default primitive renderer
pub fn init(allocator: std.mem.Allocator) void {
    rd = Renderer.init(allocator);
}

/// Destroy default primitive renderer
pub fn deinit() void {
    rd.?.deinit();
}

/// Clear primitive
pub fn clear() void {
    rd.?.clear();
}

/// Render data
pub fn flush(renderer: sdl.Renderer) !void {
    try rd.?.draw(renderer);
}

/// Draw triangle
pub const TriangleOption = struct {
    color: sdl.Color = sdl.Color.white,
};
pub fn drawTriangle(
    p0: sdl.PointF,
    p1: sdl.PointF,
    p2: sdl.PointF,
    opt: TriangleOption,
) !void {
    try rd.?.addTriangle(p0, p1, p2, opt);
}

/// Draw square
pub fn drawSquare(center: sdl.PointF, half_size: f32, opt: RectangleOption) !void {
    try rd.?.addRectangle(.{
        .x = center.x - half_size,
        .y = center.y - half_size,
        .width = 2 * half_size,
        .height = 2 * half_size,
    }, opt);
}

/// Draw rectangle
pub const RectangleOption = struct {
    color: sdl.Color = sdl.Color.white,
};
pub fn drawRectangle(rect: sdl.RectangleF, opt: RectangleOption) !void {
    try rd.?.addRectangle(rect, opt);
}

/// Draw circle
pub fn drawCircle(
    center: sdl.PointF,
    radius: f32,
    opt: EllipseOption,
) !void {
    try rd.?.addEllipse(center, radius, radius, opt);
}

/// Draw ecllipse
pub const EllipseOption = struct {
    res: u32 = 25,
    color: sdl.Color = sdl.Color.white,
};
pub fn drawEllipse(
    center: sdl.PointF,
    half_width: f32,
    half_height: f32,
    opt: EllipseOption,
) !void {
    try rd.?.addEllipse(center, half_width, half_height, opt);
}

/// 2D primitive renderer
const Renderer = struct {
    vattribs: std.ArrayList(sdl.Vertex),
    vindices: std.ArrayList(u32),

    /// Create renderer
    fn init(allocator: std.mem.Allocator) Renderer {
        return .{
            .vattribs = std.ArrayList(sdl.Vertex).init(allocator),
            .vindices = std.ArrayList(u32).init(allocator),
        };
    }

    /// Destroy renderer
    fn deinit(self: *Renderer) void {
        self.vattribs.deinit();
        self.vindices.deinit();
    }

    /// Clear renderer
    fn clear(self: *Renderer) void {
        self.vattribs.clearRetainingCapacity();
        self.vindices.clearRetainingCapacity();
    }

    /// Add a triangle
    fn addTriangle(
        self: *Renderer,
        p0: sdl.PointF,
        p1: sdl.PointF,
        p2: sdl.PointF,
        opt: TriangleOption,
    ) !void {
        const base_index = @intCast(u32, self.vattribs.items.len);
        try self.vattribs.appendSlice(&.{
            .{ .position = p0, .color = opt.color },
            .{ .position = p1, .color = opt.color },
            .{ .position = p2, .color = opt.color },
        });
        try self.vindices.appendSlice(&.{
            base_index,
            base_index + 1,
            base_index + 2,
        });
    }

    /// Add a rectangle
    fn addRectangle(self: *Renderer, rect: sdl.RectangleF, opt: RectangleOption) !void {
        const base_index = @intCast(u32, self.vattribs.items.len);
        try self.vattribs.appendSlice(&.{
            .{ .position = .{ .x = rect.x, .y = rect.y }, .color = opt.color },
            .{ .position = .{ .x = rect.x + rect.width, .y = rect.y }, .color = opt.color },
            .{ .position = .{ .x = rect.x + rect.width, .y = rect.y + rect.height }, .color = opt.color },
            .{ .position = .{ .x = rect.x, .y = rect.y + rect.height }, .color = opt.color },
        });
        try self.vindices.appendSlice(&.{
            base_index,
            base_index + 1,
            base_index + 2,
            base_index,
            base_index + 2,
            base_index + 3,
        });
    }

    /// Add a ellipse
    fn addEllipse(
        self: *Renderer,
        center: sdl.PointF,
        half_width: f32,
        half_height: f32,
        opt: EllipseOption,
    ) !void {
        var i: u32 = 0;
        const base_index = @intCast(u32, self.vattribs.items.len);
        const angle = math.tau / @intToFloat(f32, opt.res);
        try self.vattribs.append(.{
            .position = center,
            .color = opt.color,
        });
        while (i < opt.res) : (i += 1) {
            try self.vattribs.append(.{
                .position = .{
                    .x = center.x + half_width * @cos(@intToFloat(f32, i) * angle),
                    .y = center.y + half_height * @sin(@intToFloat(f32, i) * angle),
                },
                .color = opt.color,
            });
            const last_index = if (i == opt.res - 1) base_index + 1 else base_index + i + 2;
            try self.vindices.appendSlice(&.{
                base_index,
                base_index + i + 1,
                last_index,
            });
        }
    }

    /// Draw batched data
    fn draw(self: *Renderer, renderer: sdl.Renderer) !void {
        if (self.vindices.items.len == 0) return;

        try renderer.drawGeometry(
            null,
            self.vattribs.items,
            self.vindices.items,
        );
    }
};
