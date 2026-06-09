function love.conf(t)
    t.identity = "tetramaster"
    t.version = "11.5"
    t.console = true
    t.background = true

    t.window.title = "TetraMaster"
    t.window.width = 320
    t.window.height = 240
    t.window.borderless = false
    t.window.resizable = true
    t.window.minwidth = 1
    t.window.minheight = 1
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.display = 1
    t.window.highdpi = false
end
