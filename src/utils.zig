/// Graphics utils
pub const gfx = @import("utils/gfx.zig");

/// Math utils
pub const math = @import("utils/math.zig");

/// Algorithms (trigonomy etc)
pub const algo = @import("utils/algo.zig");

/// Easing utils
pub const easing = @import("utils/easing.zig");

/// Async tools
pub const async_tool = @import("utils/async.zig");

/// Generic ring data structure
pub const ring = @import("utils/ring.zig");

/// XML processing
pub const xml = @import("utils/xml.zig");

/// Trait system
pub const trait = @import("utils/trait.zig");

test "utils" {
    _ = async_tool;
    _ = xml;
    _ = ring;
    _ = trait;
}
