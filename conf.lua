function lovr.conf(t)
  t.window.resizable = true
  if arg[1] == '--res' then
    t.headset.supersample = tonumber(arg[2])
  end
end