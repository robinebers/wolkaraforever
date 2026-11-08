-- Wheel shortcuts appear under Escape > Key Bindings. A controller button can open a wheel.
BINDING_HEADER_WOLKARAMOBILE = "Mobile UI"
for i = 1, 4 do
    _G["BINDING_NAME_CLICK WolkaraMobileToggle" .. i .. ":LeftButton"] = i == 1 and "Toggle wheel" or ("Toggle wheel " .. i)
end
