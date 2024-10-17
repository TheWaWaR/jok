/// Game config options
pub const config = @import("config.zig");

/// Context of application
pub const Context = @import("context.zig").Context;
pub const JokContext = @import("context.zig").JokContext;

/// Basic types
const basic = @import("basic.zig");
pub const Point = basic.Point;
pub const Size = basic.Size;
pub const Rectangle = basic.Rectangle;
pub const Color = basic.Color;
pub const Vertex = basic.Vertex;

/// Window of App
pub const Window = @import("window.zig").Window;

/// I/O system
pub const io = @import("io.zig");
pub const Event = io.Event;

/// Graphics Renderer
pub const Renderer = @import("renderer.zig").Renderer;

/// Graphics Texture
pub const Texture = @import("texture.zig").Texture;

/// blend mode
pub const BlendMode = @import("blend.zig").BlendMode;

/// 2d rendering
pub const j2d = @import("j2d.zig");

/// 3d rendering
pub const j3d = @import("j3d.zig");

/// Font module
pub const font = @import("font.zig");

/// Misc util functions
pub const utils = @import("utils.zig");

/// Expose vendor libraries
pub usingnamespace @import("vendor.zig");

// All tests
test "all" {
    _ = j2d;
    _ = j3d;
    _ = font;
    _ = utils;
}
