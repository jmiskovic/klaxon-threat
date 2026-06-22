function lovr.conf(t)
  t.window.resizable = true
  for i, param in ipairs(arg) do
    if param == '--res' then
      t.headset.supersample = tonumber(arg[i+1])
    end
  end
end