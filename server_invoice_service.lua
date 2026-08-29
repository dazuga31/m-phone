local InvoiceService = {}

local function Text(value)
	return tostring(value or "")
end

local function CompactToken(value, fallback)
	local token = Text(value):gsub("[^%w]", ""):upper()
	return token ~= "" and token or fallback
end

local function CancelDocument(documentId)
	pcall(function()
		exports["m-documents"]:CancelDocument(documentId)
	end)
end

local function RemoveItem(holderId, rowUid)
	if holderId == "" or rowUid == "" then
		return
	end

	pcall(function()
		exports["m-inventory"]:RemoveOwnedItemByUid(holderId, rowUid)
	end)
end

function InvoiceService.NewIdentity(prefix, holderId, requestId, referenceId)
	local holderToken = CompactToken(holderId, "PLAYER"):sub(-10)
	local requestToken = CompactToken(requestId, tostring(os.time())):sub(-18)
	local referenceToken = CompactToken(referenceId, "JOB"):sub(-18)
	local base = table.concat({ prefix, referenceToken, holderToken, requestToken }, "-")
	return base:lower(), base
end

function InvoiceService.ResolveHolderId(controller, fallbackPlayerId)
	local ok, playerId = pcall(function()
		return exports["m-inventory"]:GetPlayerId(controller)
	end)

	if ok and Text(playerId) ~= "" then
		return Text(playerId)
	end

	return Text(fallbackPlayerId)
end

function InvoiceService.ResolveOwnerName(controller, holderId, fallbackName)
	local ok, profile = pcall(function()
		return exports["m-documents"]:ResolvePlayerProfile(controller, holderId, holderId)
	end)

	if ok and type(profile) == "table" then
		local fullName = Text(profile.fullName or profile.name)
		if fullName ~= "" then
			return fullName
		end
	end

	return Text(fallbackName) ~= "" and Text(fallbackName) or "Contractor"
end

function InvoiceService.Issue(context)
	context = type(context) == "table" and context or {}

	local controller = context.controller
	local holderId = Text(context.holderId)
	local itemId = Text(context.itemId)
	local document = type(context.document) == "table" and context.document or nil

	if not controller or holderId == "" or itemId == "" or not document then
		return false, "invalid_invoice_context"
	end

	local documentId = Text(document.id)
	local documentType = Text(document.type)
	local documentNumber = Text(document.number)
	if documentId == "" or documentType == "" or documentNumber == "" then
		return false, "invalid_document_metadata"
	end

	local canGiveOk, canGive, canGiveReason = pcall(function()
		return exports["m-inventory"]:CanGiveItem(holderId, itemId, {
			qty = 1,
			containerId = "player",
			controller = controller,
			noStack = true,
		})
	end)
	if not canGiveOk then
		return false, "inventory_unavailable"
	end
	if canGive ~= true then
		return false, Text(canGiveReason) ~= "" and Text(canGiveReason) or "inventory_full"
	end

	document.holderId = holderId
	document.status = "pending"
	document.issueRequestId = Text(document.issueRequestId) ~= "" and Text(document.issueRequestId)
		or ("invoice-print:" .. documentId)

	local createOk, created, createReason = pcall(function()
		return exports["m-documents"]:CreatePendingDocument(document)
	end)
	if not createOk then
		return false, "document_service_unavailable"
	end
	if created ~= true then
		return false, Text(createReason) ~= "" and Text(createReason) or "document_create_failed"
	end

	local meta = type(context.meta) == "table" and context.meta or {}
	meta.documentId = documentId
	meta.documentType = documentType
	meta.documentNumber = documentNumber
	meta.holderId = holderId

	local giveOk, itemGiven, itemReason, itemResult = pcall(function()
		return exports["m-inventory"]:GiveItem(holderId, itemId, {
			qty = 1,
			containerId = "player",
			controller = controller,
			noStack = true,
			notify = true,
			meta = meta,
		})
	end)
	if not giveOk or itemGiven ~= true then
		CancelDocument(documentId)
		return false, Text(itemReason) ~= "" and Text(itemReason) or "invoice_item_failed"
	end

	local rowUid = type(itemResult) == "table" and Text(itemResult.uid) or ""
	local activateOk, activated = pcall(function()
		return exports["m-documents"]:ActivateDocument(documentId)
	end)
	if not activateOk or activated ~= true then
		RemoveItem(holderId, rowUid)
		CancelDocument(documentId)
		return false, "document_activation_failed"
	end

	return true, "ok", {
		documentId = documentId,
		documentNumber = documentNumber,
		itemUid = rowUid,
	}
end

return InvoiceService
