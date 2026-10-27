-- ryoku-clamshell owns the shared lid-close policy. It sends non-docked closes
-- through the shell's secure suspend transaction; live docked mode hands the
-- covered panel to the external display. Opening clears only the panel's
-- disabled flag, preserving mode, scale and position. locked = fires while
-- qylock is active too, so display handoff remains correct across resume.
local function sync_physical_lid()
    hl.exec_cmd("command -v ryoku-clamshell >/dev/null 2>&1 && ryoku-clamshell lid sync")
end

-- Hyprland binds a switch by its device name, and only ACPI laptops call theirs
-- "Lid Switch" (an Apple Silicon Mac's is "Apple SMC power/lid events"), so bind
-- every input device whose switch capabilities include SW_LID (bit 0).
local function lid_switch_names()
    local p = io.popen([[
        for d in /sys/class/input/input*; do
            sw=$(cat "$d/capabilities/sw" 2>/dev/null) || continue
            [ $((0x${sw##* } & 1)) -eq 1 ] && cat "$d/name"
        done
    ]])
    if not p then return {} end
    local names = {}
    for name in p:lines() do
        if name ~= "" then names[#names + 1] = name end
    end
    p:close()
    return names
end

hl.on("hyprland.start", sync_physical_lid)
hl.on("config.reloaded", sync_physical_lid)
for _, name in ipairs(lid_switch_names()) do
    hl.bind("switch:on:" .. name,  hl.dsp.exec_cmd("command -v ryoku-clamshell >/dev/null 2>&1 && ryoku-clamshell lid close"), { locked = true })
    hl.bind("switch:off:" .. name, hl.dsp.exec_cmd("command -v ryoku-clamshell >/dev/null 2>&1 && ryoku-clamshell lid open"),  { locked = true })
end
