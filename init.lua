local selfname = ...
return setmetatable({}, {
    __call = function(t, module)
        t[module] = require(selfname.."."..module.."."..module)
        return t[module]
    end,
    __index = function(t,k)
        return t(k)
    end
})

