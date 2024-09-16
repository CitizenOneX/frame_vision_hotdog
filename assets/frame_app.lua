local data = require('data.min')
local battery = require('battery.min')
local camera = require('camera.min')
local sprite = require('sprite.min')

-- Phone to Frame flags
CAMERA_SETTINGS_MSG = 0x0d
HOTDOG_MSG = 0x0e
HOTDOG_SPRITE = 0x20
HOTDOG_TEXT = 0x21
NOT_HOTDOG_SPRITE = 0x22
NOT_HOTDOG_TEXT = 0x23

-- register the message parser so it's automatically called when matching data comes in
data.parsers[CAMERA_SETTINGS_MSG] = camera.parse_camera_settings
data.parsers[HOTDOG_SPRITE] = sprite.parse_sprite
data.parsers[HOTDOG_TEXT] = sprite.parse_sprite
data.parsers[NOT_HOTDOG_SPRITE] = sprite.parse_sprite
data.parsers[NOT_HOTDOG_TEXT] = sprite.parse_sprite

-- Code is just the msg_code and a single byte
function parse_code(data)
	local code = {}
	code.value = string.byte(data, 1)
	return code
end

data.parsers[HOTDOG_MSG] = parse_code

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
		-- process any raw data items, if ready (parse into take_photo, then clear data.app_data_block)
		local items_ready = data.process_raw_items()

		if items_ready > 0 then

			if (data.app_data[CAMERA_SETTINGS_MSG] ~= nil) then
				print('camera_settings message')
				rc, err = pcall(camera.camera_capture_and_send, data.app_data[CAMERA_SETTINGS_MSG])

				if rc == false then
					print(err)
				end
				-- clear the message
				data.app_data[CAMERA_SETTINGS_MSG] = nil
			end

			if (data.app_data[HOTDOG_MSG] ~= nil) then
				print('hotdog message')

				if (data.app_data[HOTDOG_MSG].value == 1) then
					frame.display.text('Hotdog!', 1, 1)

					if (data.app_data[HOTDOG_SPRITE] ~= nil) then
						print('showing hotdog sprite')
						local spr = data.app_data[HOTDOG_SPRITE]
						frame.display.bitmap(400, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
					if (data.app_data[HOTDOG_TEXT] ~= nil) then
						print('showing hotdog text')
						local spr = data.app_data[HOTDOG_TEXT]
						frame.display.bitmap(1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
				else
					frame.display.text('Not Hotdog!', 1, 1)

					if (data.app_data[NOT_HOTDOG_SPRITE] ~= nil) then
						print('showing not hotdog sprite')
						local spr = data.app_data[NOT_HOTDOG_SPRITE]
						frame.display.bitmap(400, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					end
					if (data.app_data[NOT_HOTDOG_TEXT] ~= nil) then
						print('showing hotdog text')
						local spr = data.app_data[NOT_HOTDOG_TEXT]
						frame.display.bitmap(1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
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