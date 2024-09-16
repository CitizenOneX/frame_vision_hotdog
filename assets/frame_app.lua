local data = require('data.min')
local battery = require('battery.min')
local camera = require('camera.min')
local sprite = require('sprite.min')
local code = require('code.min')

-- Phone to Frame flags
CAMERA_SETTINGS_MSG = 0x0d
HOTDOG_MSG = 0x0e
HOTDOG_SPRITE = 0x20
HOTDOG_TEXT = 0x21
NOT_HOTDOG_SPRITE = 0x22
NOT_HOTDOG_TEXT = 0x23

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[CAMERA_SETTINGS_MSG] = camera.parse_camera_settings
data.parsers[HOTDOG_MSG] = code.parse_code
data.parsers[HOTDOG_SPRITE] = sprite.parse_sprite
data.parsers[HOTDOG_TEXT] = sprite.parse_sprite
data.parsers[NOT_HOTDOG_SPRITE] = sprite.parse_sprite
data.parsers[NOT_HOTDOG_TEXT] = sprite.parse_sprite

function clear_display()
    frame.display.text(" ", 1, 1)
    frame.display.show()
    frame.sleep(0.04)
end

-- Main app loop
function app_loop()
	clear_display()
    local last_batt_update = 0

	while true do
		-- process any raw data items, if ready
		local items_ready = data.process_raw_items()

		-- one or more full messages received
		if items_ready > 0 then

			-- camera_settings message to take a photo
			if (data.app_data[CAMERA_SETTINGS_MSG] ~= nil) then
				rc, err = pcall(camera.camera_capture_and_send, data.app_data[CAMERA_SETTINGS_MSG])

				if rc == false then
					print(err)
				end

				-- clear the message
				data.app_data[CAMERA_SETTINGS_MSG] = nil
			end

			-- hotdog classification 0 or 1
			if (data.app_data[HOTDOG_MSG] ~= nil) then

				if (data.app_data[HOTDOG_MSG].value == 1) then

					if (data.app_data[HOTDOG_SPRITE] ~= nil) then
						local spr = data.app_data[HOTDOG_SPRITE]
						-- 128 x 128 px
						frame.display.bitmap(450, 136, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
					if (data.app_data[HOTDOG_TEXT] ~= nil) then
						local spr = data.app_data[HOTDOG_TEXT]
						-- 227 x 67 px
						frame.display.bitmap(203, 166, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
				else
					if (data.app_data[NOT_HOTDOG_SPRITE] ~= nil) then
						local spr = data.app_data[NOT_HOTDOG_SPRITE]
						-- 128 x 128 px
						frame.display.bitmap(450, 136, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
					if (data.app_data[NOT_HOTDOG_TEXT] ~= nil) then
						local spr = data.app_data[NOT_HOTDOG_TEXT]
						-- 361 x 67 px
						frame.display.bitmap(69, 166, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
				end

				frame.display.show()
				-- TODO could also set a timer to show only for while

				-- clear the message
				data.app_data[HOTDOG_MSG] = nil
			end
		end

        -- periodic battery level updates, 120s for a camera app
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- run the main app loop
app_loop()