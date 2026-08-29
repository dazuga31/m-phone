local Bridge = {}

function Bridge.GetPlayer()
	return nil, "m_core_not_implemented"
end

function Bridge.AddCash()
	return false, "m_core_not_implemented"
end

function Bridge.RemoveCash()
	return false, "m_core_not_implemented"
end

function Bridge.Database()
	return nil, "m_core_not_implemented"
end

return Bridge

