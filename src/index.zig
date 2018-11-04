//  Copyright (c) 2018 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");
const builtin = @import("builtin");

const io = std.io;
const os = std.os;

const windows = os.windows;
const posix = os.posix;

const FOREGROUND_BLACK = u16(0);
const FOREGROUND_BLUE = u16(1);
const FOREGROUND_GREEN = u16(2);
const FOREGROUND_AQUA= u16(3);
const FOREGROUND_RED = u16(4);
const FOREGROUND_PURPLE = u16(5);
const FOREGROUND_YELLOW = u16(6);
const FOREGROUND_WHITE = u16(7);
const FOREGROUND_INTENSITY = u16(8);

const BACKGROUND_BLACK = FOREGROUND_BLACK << 4;
const BACKGROUND_BLUE = FOREGROUND_BLUE << 4;
const BACKGROUND_GREEN = FOREGROUND_GREEN << 4;
const BACKGROUND_AQUA= FOREGROUND_AQUA << 4;
const BACKGROUND_RED = FOREGROUND_RED << 4;
const BACKGROUND_PURPLE = FOREGROUND_PURPLE << 4;
const BACKGROUND_YELLOW = FOREGROUND_YELLOW << 4;
const BACKGROUND_WHITE = FOREGROUND_WHITE << 4;
const BACKGROUND_INTENSITY = FOREGROUND_INTENSITY << 4;

const COMMON_LVB_REVERSE_VIDEO = 0x4000;
const COMMON_LVB_UNDERSCORE = 0x8000;

const OutStream = os.File.OutStream;

pub const Color = enum.{
    Black,
    Blue,
    Green,
    Aqua,
    Red,
    Purple,
    Yellow,
    White,
};

pub const Attribute = enum.{
    Bright,
    Reversed,
    Underlined,
};

pub const Mode = enum.{
    ForeGround,
    BackGround,
};

pub fn supportsAnsi(handle: os.FileHandle) bool {
    if (builtin.os == builtin.Os.windows) {
        var out: windows.DWORD = undefined;
        return windows.GetConsoleMode(handle, &out) == 0;
    } else {
        if (builtin.link_libc) {
            return std.c.isatty(handle) != 0;
        } else {
            return posix.isatty(handle);
        }
    }
}

pub const ColoredOutStream = struct.{
    const Self = @This();

    const Error = error.{
        InvalidMode,
    };

    default_attrs: windows.WORD,
    current_attrs: windows.WORD,
    back_attr: []const u8,
    fore_attr: []const u8,

    file: os.File,
    file_stream: OutStream,
    out_stream: ?*OutStream.Stream,
    
    pub fn new(file: os.File) Self {
        // TODO handle error
        var info: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        _ = windows.GetConsoleScreenBufferInfo(file.handle, &info);

        return Self.{
            .file = file,
            .file_stream = file.outStream(),
            .out_stream = null,
            .default_attrs = info.wAttributes,
            .current_attrs = info.wAttributes,
            .back_attr = "",
            .fore_attr = "",
        };
    }

    // can't be done in `new` because of no copy-elision
    fn outStream(self: *Self) *OutStream.Stream {
        if (self.out_stream) |out_stream| {
            return out_stream;
        } else {
            self.out_stream = &self.file_stream.stream;
            return self.out_stream.?;
        }
    }

    fn setAttributeWindows(self: *Self, attr: Attribute, mode: ?Mode) !void {
        if (mode == null and attr == Attribute.Bright) {
            return error.InvalidMode;
        }

        self.current_attrs |= switch (attr) {
                Attribute.Reversed   => COMMON_LVB_REVERSE_VIDEO,
                Attribute.Underlined => COMMON_LVB_UNDERSCORE,
                Attribute.Bright     => switch (mode.?) {
                    Mode.ForeGround => FOREGROUND_INTENSITY,
                    Mode.BackGround => BACKGROUND_INTENSITY,
                },
            };

        // TODO handle errors
        _ = windows.SetConsoleTextAttribute(self.file.handle, self.current_attrs);
    }

    fn setAttribute(self: *Self, attr: Attribute, mode: ?Mode) !void {
        if (builtin.os == builtin.Os.windows and !supportsAnsi(self.file.handle)) {
            try self.setAttributeWindows(attr, mode);
        } else {
            var out = self.outStream();
            if (mode == null and attr == Attribute.Bright) {
                return error.InvalidMode;
            }
            switch (attr) {
                Attribute.Bright     => try out.write("\x1b[1m"),
                Attribute.Underlined => try out.write("\x1b[4m"),
                Attribute.Reversed   => try out.write("\x1b[7m"),
            }
        }
    }

    fn setColorWindows(self: *Self, color: Color, mode: Mode) void {
        self.current_attrs |= switch (mode) {
            Mode.ForeGround => switch (color) {
                Color.Black  => FOREGROUND_BLACK,
                Color.Blue   => FOREGROUND_BLUE,
                Color.Green  => FOREGROUND_GREEN,
                Color.Aqua   => FOREGROUND_AQUA,
                Color.Red    => FOREGROUND_RED,
                Color.Purple => FOREGROUND_PURPLE,
                Color.Yellow => FOREGROUND_YELLOW,
                Color.White  => FOREGROUND_WHITE,
            },
            Mode.BackGround => switch (color) {
                Color.Black  => BACKGROUND_BLACK,
                Color.Blue   => BACKGROUND_BLUE,
                Color.Green  => BACKGROUND_GREEN,
                Color.Aqua   => BACKGROUND_AQUA,
                Color.Red    => BACKGROUND_RED,
                Color.Purple => BACKGROUND_PURPLE,
                Color.Yellow => BACKGROUND_YELLOW,
                Color.White  => BACKGROUND_WHITE,
            }
        };

        // TODO handle errors
        _ = windows.SetConsoleTextAttribute(self.file.handle, self.current_attrs);
    }

    pub fn setColor(self: *Self, color: Color, mode: Mode, attributes: ?[]const Attribute) !void {
        if (attributes) |attrs| {
            for (attrs) |attr| {
                try self.setAttribute(attr, mode);
            }
        }

        if (builtin.os == builtin.Os.windows and !supportsAnsi(self.file.handle)) {
            self.setColorWindows(color, mode);
        } else {
            var out = self.outStream();
            switch (mode) {
                Mode.ForeGround => switch (color) {
                    Color.Black  => try out.write("\x1b[30m"),
                    Color.Red    => try out.write("\x1b[31m"),
                    Color.Green  => try out.write("\x1b[32m"),
                    Color.Yellow => try out.write("\x1b[33m"),
                    Color.Blue   => try out.write("\x1b[34m"),
                    Color.Purple => try out.write("\x1b[35m"),
                    Color.Aqua   => try out.write("\x1b[36m"),
                    Color.White  => try out.write("\x1b[37m"),
                },
                Mode.BackGround => switch (color) {
                    Color.Black  => try out.write("\x1b[40m"),
                    Color.Red    => try out.write("\x1b[41m"),
                    Color.Green  => try out.write("\x1b[42m"),
                    Color.Yellow => try out.write("\x1b[43m"),
                    Color.Blue   => try out.write("\x1b[44m"),
                    Color.Purple => try out.write("\x1b[45m"),
                    Color.Aqua   => try out.write("\x1b[46m"),
                    Color.White  => try out.write("\x1b[47m"),
                }
            }
        }
    }

    pub fn reset(self: *Self) !void {
        if (builtin.os == builtin.Os.windows and !supportsAnsi(self.file.handle)) {
            // TODO handle errors
            _ = windows.SetConsoleTextAttribute(self.file.handle, self.default_attrs);
        } else {
            var out = self.outStream();
            try out.write("\x1b[0m");
        }
        self.current_attrs = self.default_attrs;
    }
};

test "ColoredOutStream" {
    const attrs = []Attribute.{ Attribute.Bright, Attribute.Underlined };
    var color_stream = ColoredOutStream.new(try io.getStdOut());
    defer color_stream.reset() catch {};

    var stdout = color_stream.outStream();

    try color_stream.setColor(Color.Red, Mode.ForeGround, attrs);
    try stdout.print("\nhi\n");
    os.time.sleep(1000000000);
    try stdout.print("hey\n");
    os.time.sleep(1000000000);
    try stdout.print("hello\n");
    os.time.sleep(1000000000);
    try stdout.print("greetings\n");
    os.time.sleep(1000000000);
    try stdout.print("salutations\n");
    os.time.sleep(1000000000);
    try stdout.print("goodbye\n");
    os.time.sleep(1000000000);
}
