-- server/db.lua

local DB = {}

local DB_FILE = "m-phone.sqlite"

local isReady = false

local function EnsureReady()
	if not isReady then
		DB.Init()
	end
end

-- =========================
-- Helpers: TArray-safe rows
-- =========================

local function RowsCount(rows)
	if rows == nil then return 0 end

	for _, methodName in ipairs({ "Num", "Length", "Count" }) do
		local okMethod, method = pcall(function() return rows[methodName] end)
		if okMethod and method ~= nil then
			local okValue, value = pcall(method, rows)
			if okValue and tonumber(value) ~= nil then return math.max(0, math.floor(tonumber(value))) end
		end
	end

	if type(rows) == "table" then return #rows end
	return 0
end

local function RowAt(rows, index)
	if rows == nil then return nil end
	local oneBasedIndex = math.max(1, math.floor(tonumber(index) or 1))
	local count = RowsCount(rows)
	if count <= 0 or oneBasedIndex > count then return nil end

	local okGetter, getter = pcall(function() return rows.Get end)
	if okGetter and getter ~= nil then
		local okRow, row = pcall(getter, rows, oneBasedIndex - 1)
		return okRow and row or nil
	end

	if type(rows) == "table" then return rows[oneBasedIndex] end
	return nil
end

local function RowsFirst(rows)
	if not rows then return nil end
	local n = RowsCount(rows)
	if n <= 0 then return nil end
	return RowAt(rows, 1)
end

-- =========================
-- RowGet (HELIX-safe)
-- =========================

function DB.RowGet(row, ...)
	if not row then return nil end

	local cols = nil

	-- table row with table Columns
	if type(row) == "table" and type(row.Columns) == "table" then
		cols = row.Columns
	end

	-- HELIX rows may be userdata or Lua tables with Columns stored as a TMap userdata.
	if cols == nil and (type(row) == "userdata" or type(row) == "table") then
		local ok, c = pcall(function() return row.Columns end)
		if ok then cols = c end
	end

	for i = 1, select("#", ...) do
		local key = select(i, ...)

		-- HELIX TMap: cols:Find("ColumnName")
		if cols ~= nil then
			local okFind, find = pcall(function() return cols.Find end)
			if okFind and find ~= nil then
				local ok, v = pcall(find, cols, key)
				if ok and v ~= nil then return v end
			end
		end

		-- classic table Columns
		if type(cols) == "table" then
			local ok, v = pcall(function() return cols[key] end)
			if ok and v ~= nil then return v end
		end

		-- last fallback: plain table row
		if type(row) == "table" then
			local ok, v = pcall(function() return row[key] end)
			if ok and v ~= nil then return v end
		end
	end

	return nil
end

function DB.RowsFirst(rows)
	return RowsFirst(rows)
end

function DB.RowsCount(rows)
	return RowsCount(rows)
end

function DB.RowAt(rows, index)
	return RowAt(rows, index)
end

-- =========================
-- Time helpers
-- =========================

local function NowSec()
	return os.time()
end

local function Now()
	return NowSec()
end

local function NowMs()
	return math.floor(os.time() * 1000)
end

local function LogSchema(msg)
	print("[m-phone][db][schema] " .. tostring(msg))
end

local function Log(msg)
	print("[m-phone][db] " .. tostring(msg))
end

local function LogErr(msg)
	print("[m-phone][db][error] " .. tostring(msg))
end

-- =========================
-- Numeric helpers
-- =========================

local function ToInt(v)
	return math.floor(tonumber(v) or 0)
end

-- шукаємо рахунок по AccountId
-- =========================
-- DDL helper
-- =========================

local function ExecDDL(name, sql)
	Log("ensure table: " .. tostring(name))

	local ok, result = pcall(function()
		return Database.Execute(sql, {})
	end)
	if ok and result == true then
		Log("ensure table ok: " .. tostring(name))
		return true
	end

	LogErr("ensure table failed: " .. tostring(name) .. " result=" .. tostring(result))
	error("DB.Init: Failed to create table " .. tostring(name))
end

local function TryExec(name, sql)
	local ok, result = pcall(function()
		return Database.Execute(sql, {})
	end)
	if ok and result == true then
		Log("ddl ok: " .. tostring(name))
		return true
	elseif not ok then
		LogErr("ddl failed (ignored): " .. tostring(name) .. " err=" .. tostring(result))
	else
		LogErr("ddl failed (ignored): " .. tostring(name) .. " result=" .. tostring(result))
	end
	return false
end

-- =========================
-- Schema guard (tables / columns)
-- =========================

local function TableExists(name)
	local rows = Database.Select(
		"SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
		{ tostring(name) }
	)
	return RowsCount(rows) > 0
end

local function ColumnExists(tableName, columnName)
	local t = tostring(tableName):gsub("[^%w_]", "")
	local col = tostring(columnName):gsub("[^%w_]", "")

	local rows = Database.Select("PRAGMA table_info(" .. t .. ")")
	local n = RowsCount(rows)

	if n <= 0 then
		LogSchema("PRAGMA table_info(" .. t .. ") -> empty")
		return false
	end

	LogSchema("PRAGMA table_info(" .. t .. ") rows=" .. tostring(n))

	for i = 1, n do
		local r = RowAt(rows, i)
		if r then
			local v = DB.RowGet(r, "name", "Name", "NAME", 2, 1)
			if v ~= nil and tostring(v) == col then
				return true
			end
		end
	end

	return false
end

local function EnsureTable(name, ddl)
	if TableExists(name) then
		LogSchema("table OK: " .. name)
		return
	end

	LogSchema("table MISSING -> create: " .. name)
	ExecDDL(name, ddl)
end

local function EnsureColumn(tableName, columnName, columnDDL)
	if ColumnExists(tableName, columnName) then
		LogSchema("column OK: " .. tableName .. "." .. columnName)
		return
	end

	LogSchema("column MISSING -> add: " .. tableName .. "." .. columnName)
	local ok = TryExec(
		("addcol_%s_%s"):format(tableName, columnName),
		("ALTER TABLE %s ADD COLUMN %s"):format(tableName, columnDDL)
	)
	if ok and ColumnExists(tableName, columnName) then
		LogSchema("column ADDED: " .. tableName .. "." .. columnName)
	elseif ok then
		LogSchema("column add executed but not visible: " .. tableName .. "." .. columnName)
	end
end

-- =========================
-- Init + Tables
-- =========================

local function LegacyLocalDomainSchemaEnabled()
	return Config and Config.LegacyLocalDomainSchema == true
end

function DB.Schema()
	LogSchema("schema start")

	-- =========================
	-- Players
	-- =========================
	EnsureTable("Players", [[
		CREATE TABLE IF NOT EXISTS Players (
			ID TEXT PRIMARY KEY,
			Name TEXT NOT NULL,
			Cash INTEGER NOT NULL DEFAULT 0,
			CreatedAt INTEGER NOT NULL,
			LastSeen INTEGER NOT NULL
		)
	]])

	-- =========================
	-- PlayerSettings
	-- =========================
	EnsureTable("PlayerSettings", [[
		CREATE TABLE IF NOT EXISTS PlayerSettings (
			PlayerID TEXT PRIMARY KEY,
			Language TEXT NOT NULL DEFAULT 'en',
			Volume REAL NOT NULL DEFAULT 0.8,
			UpdatedAt INTEGER NOT NULL
		)
	]])


	-- Сolumns for "First Run Setup"
	EnsureColumn("PlayerSettings", "SetupCompleted", "SetupCompleted INTEGER NOT NULL DEFAULT 0")
	EnsureColumn("PlayerSettings", "PinEnabled", "PinEnabled INTEGER NOT NULL DEFAULT 0")
	EnsureColumn("PlayerSettings", "PinCode", "PinCode TEXT")
	EnsureColumn("PlayerSettings", "FaceIdEnabled", "FaceIdEnabled INTEGER NOT NULL DEFAULT 0")
	EnsureColumn("PlayerSettings", "DeviceName", "DeviceName TEXT NOT NULL DEFAULT 'Union Device'")
	EnsureColumn("PlayerSettings", "UIFrameScale", "UIFrameScale REAL NOT NULL DEFAULT 1.0")
	EnsureColumn("PlayerSettings", "UIOffsetX", "UIOffsetX REAL NOT NULL DEFAULT 0.0")
	EnsureColumn("PlayerSettings", "UIOffsetY", "UIOffsetY REAL NOT NULL DEFAULT 0.0")
	EnsureColumn("PlayerSettings", "UIEditMode", "UIEditMode INTEGER NOT NULL DEFAULT 0")
	EnsureColumn("PlayerSettings", "SilentMode", "SilentMode INTEGER NOT NULL DEFAULT 0")
	EnsureColumn("PlayerSettings", "Vibration", "Vibration INTEGER NOT NULL DEFAULT 1")
	EnsureColumn("PlayerSettings", "DoNotDisturb", "DoNotDisturb INTEGER NOT NULL DEFAULT 0")
	EnsureColumn("PlayerSettings", "AllowFavoriteCalls", "AllowFavoriteCalls INTEGER NOT NULL DEFAULT 1")
	EnsureColumn("PlayerSettings", "MissedCallNotifications", "MissedCallNotifications INTEGER NOT NULL DEFAULT 1")
	EnsureColumn("PlayerSettings", "HomeLayoutJson", "HomeLayoutJson TEXT NOT NULL DEFAULT ''")
	EnsureColumn("PlayerSettings", "TabletLayoutJson", "TabletLayoutJson TEXT NOT NULL DEFAULT ''")

	-- =========================
	-- ShopProducts
	-- =========================
	if LegacyLocalDomainSchemaEnabled() then
	EnsureTable("ShopProducts", [[
		CREATE TABLE IF NOT EXISTS ShopProducts (
			ID TEXT PRIMARY KEY,
			Json TEXT NOT NULL,
			UpdatedAt INTEGER NOT NULL
		)
	]])

	-- =========================
	-- Owned shops
	-- =========================
	EnsureTable("OwnedShops", [[
		CREATE TABLE IF NOT EXISTS OwnedShops (
			ID TEXT PRIMARY KEY,
			Label TEXT NOT NULL,
			Type TEXT NOT NULL DEFAULT 'default',
			Status TEXT NOT NULL DEFAULT 'setup',
			OwnerID TEXT,
			BusinessPrice INTEGER NOT NULL DEFAULT 0,
			Balance INTEGER NOT NULL DEFAULT 0,
			TodaySales INTEGER NOT NULL DEFAULT 0,
			StockValue INTEGER NOT NULL DEFAULT 0,
			Coords TEXT,
			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL
		)
	]])
	EnsureColumn("OwnedShops", "BusinessPrice", "BusinessPrice INTEGER NOT NULL DEFAULT 0")
	EnsureColumn("OwnedShops", "TodaySalesDay", "TodaySalesDay TEXT NOT NULL DEFAULT ''")

	EnsureTable("OwnedShopProducts", [[
		CREATE TABLE IF NOT EXISTS OwnedShopProducts (
			ShopID TEXT NOT NULL,
			ProductID TEXT NOT NULL,
			Label TEXT NOT NULL,
			Category TEXT NOT NULL DEFAULT 'General',
			PricePence INTEGER NOT NULL DEFAULT 0,
			Stock INTEGER NOT NULL DEFAULT 0,
			MaxStock INTEGER NOT NULL DEFAULT 100,
			MaxOrderQty INTEGER NOT NULL DEFAULT 25,
			Enabled INTEGER NOT NULL DEFAULT 1,
			UpdatedAt INTEGER NOT NULL,
			PRIMARY KEY (ShopID, ProductID)
		)
	]])

	EnsureColumn("OwnedShopProducts", "MaxOrderQty", "MaxOrderQty INTEGER NOT NULL DEFAULT 25")

	EnsureTable("OwnedShopLedger", [[
		CREATE TABLE IF NOT EXISTS OwnedShopLedger (
			ID TEXT PRIMARY KEY,
			ShopID TEXT NOT NULL,
			Amount INTEGER NOT NULL,
			Type TEXT NOT NULL,
			Reason TEXT,
			MetaJson TEXT,
			CreatedAt INTEGER NOT NULL
		)
	]])

	EnsureTable("OwnedShopTransactions", [[
		CREATE TABLE IF NOT EXISTS OwnedShopTransactions (
			ID TEXT PRIMARY KEY,
			ShopID TEXT NOT NULL,
			BuyerID TEXT NOT NULL,
			ItemsJson TEXT NOT NULL,
			SubtotalPence INTEGER NOT NULL,
			VatPence INTEGER NOT NULL,
			TotalPence INTEGER NOT NULL,
			PaymentMethod TEXT NOT NULL,
			CreatedAt INTEGER NOT NULL
		)
	]])

	EnsureTable("ShopSupplyOrders", [[
		CREATE TABLE IF NOT EXISTS ShopSupplyOrders (
			ID TEXT PRIMARY KEY,
			ShopID TEXT NOT NULL,
			ProductID TEXT NOT NULL,
			Qty INTEGER NOT NULL,
			GoodsCostPence INTEGER NOT NULL DEFAULT 0,
			DriverFeePence INTEGER NOT NULL DEFAULT 0,
			TotalCostPence INTEGER NOT NULL DEFAULT 0,
			TruckerOrderID TEXT,
			Status TEXT NOT NULL DEFAULT 'pending_trucker',
			CreatedBy TEXT,
			MetaJson TEXT,
			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL,
			DeliveredAt INTEGER NOT NULL DEFAULT 0
		)
	]])
	end

	-- =========================
	-- ChatConversations (NEW)
	-- =========================
	EnsureTable("ChatConversations", [[
		CREATE TABLE IF NOT EXISTS ChatConversations (
			OwnerPid TEXT NOT NULL,
			ConvId TEXT NOT NULL,

			AppId TEXT NOT NULL DEFAULT 'chat',
			Title TEXT NOT NULL DEFAULT 'Chat',

			LastMsgAt INTEGER NOT NULL DEFAULT 0,
			LastMsgPreview TEXT NOT NULL DEFAULT '',

			UnreadCount INTEGER NOT NULL DEFAULT 0,

			UpdatedAt INTEGER NOT NULL,

			PRIMARY KEY (OwnerPid, ConvId)
		)
	]])

	-- =========================
	-- ChatMessages (NEW)
	-- =========================
	EnsureTable("ChatMessages", [[
		CREATE TABLE IF NOT EXISTS ChatMessages (
			OwnerPid TEXT NOT NULL,
			ConvId TEXT NOT NULL,

			MsgId TEXT NOT NULL,

			CreatedAt INTEGER NOT NULL,
			Sender TEXT NOT NULL DEFAULT 'system',
			Text TEXT NOT NULL,

			MetaJson TEXT,

			PRIMARY KEY (OwnerPid, ConvId, MsgId)
		)
	]])

		-- =========================
	-- CourierProfiles
	-- =========================
	if LegacyLocalDomainSchemaEnabled() then
	EnsureTable("CourierProfiles", [[
		CREATE TABLE IF NOT EXISTS CourierProfiles (
			PlayerID TEXT PRIMARY KEY,
			Level INTEGER NOT NULL DEFAULT 1,
			Rating REAL NOT NULL DEFAULT 5.0,
			CompletedJobs INTEGER NOT NULL DEFAULT 0,
			TotalEarned INTEGER NOT NULL DEFAULT 0,
			SkillPoints INTEGER NOT NULL DEFAULT 0,
			UpdatedAt INTEGER NOT NULL
		)
	]])

	-- =========================
	-- CourierJobs
	-- =========================
	EnsureTable("CourierJobs", [[
		CREATE TABLE IF NOT EXISTS CourierJobs (
			ID TEXT PRIMARY KEY,
			PlayerID TEXT,
			Title TEXT NOT NULL,
			Customer TEXT,
			Pickup TEXT,
			Dropoff TEXT,
			Reward INTEGER NOT NULL DEFAULT 0,
			DistanceKm REAL NOT NULL DEFAULT 0,
			Status TEXT NOT NULL DEFAULT 'available',
			Priority TEXT NOT NULL DEFAULT 'normal',
			RequiredSkillsJson TEXT,
			Notes TEXT,
			InvoiceNumber TEXT,
			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL,
			CompletedAt INTEGER
		)
	]])

	-- =========================
	-- CourierInvoices
	-- =========================
	EnsureTable("CourierInvoices", [[
		CREATE TABLE IF NOT EXISTS CourierInvoices (
			InvoiceID TEXT PRIMARY KEY,
			PlayerID TEXT NOT NULL,
			JobID TEXT NOT NULL,
			Status TEXT NOT NULL DEFAULT 'printed',
			MetaJson TEXT,
			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL
		)
	]])

		-- =========================
	-- TruckerProfiles
	-- =========================
	EnsureTable("TruckerProfiles", [[
		CREATE TABLE IF NOT EXISTS TruckerProfiles (
			PlayerID TEXT PRIMARY KEY,
			Name TEXT,
			Phone TEXT,
			Level INTEGER NOT NULL DEFAULT 1,
			SkillsJson TEXT,
			UpdatedAt INTEGER NOT NULL
		)
	]])

	-- =========================
	-- TruckerOrders
	-- =========================
	EnsureTable("TruckerOrders", [[
		CREATE TABLE IF NOT EXISTS TruckerOrders (
			ID TEXT PRIMARY KEY,

			AssignedPlayerID TEXT,

			Title TEXT NOT NULL,
			ClientName TEXT NOT NULL,
			CargoName TEXT NOT NULL,
			CargoClass TEXT NOT NULL DEFAULT 'standard',
			WeightKg REAL NOT NULL DEFAULT 0,

			PickupLabel TEXT NOT NULL,
			DropoffLabel TEXT NOT NULL,

			DistanceKm REAL NOT NULL DEFAULT 0,
			Reward INTEGER NOT NULL DEFAULT 0,
			Deposit INTEGER NOT NULL DEFAULT 0,

			VehicleClass TEXT,
			TrailerRequired INTEGER NOT NULL DEFAULT 0,

			Status TEXT NOT NULL DEFAULT 'available',
			EstimatedMinutes INTEGER NOT NULL DEFAULT 0,
			DeadlineAt INTEGER,
			Description TEXT,

			MinLevel INTEGER NOT NULL DEFAULT 1,
			RequiredSkillsJson TEXT,

			IconImage TEXT,
			TruckImage TEXT,
			TrailerImage TEXT,
			CargoImage TEXT,

			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL
		)
	]])
	end

	EnsureTable("PhoneProfiles", [[
		CREATE TABLE IF NOT EXISTS PhoneProfiles (
			PlayerID TEXT PRIMARY KEY,
			CitizenID TEXT NOT NULL UNIQUE,
			PhoneNumber TEXT NOT NULL UNIQUE,
			DisplayName TEXT NOT NULL DEFAULT 'Unknown',
			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL
		)
	]])

	EnsureTable("PhoneContacts", [[
		CREATE TABLE IF NOT EXISTS PhoneContacts (
			OwnerPlayerID TEXT NOT NULL,
			ContactID TEXT NOT NULL,
			ContactName TEXT NOT NULL,
			PhoneNumber TEXT NOT NULL,
			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL,
			PRIMARY KEY (OwnerPlayerID, ContactID),
			UNIQUE (OwnerPlayerID, PhoneNumber)
		)
	]])

	EnsureTable("PhoneContactFlags", [[
		CREATE TABLE IF NOT EXISTS PhoneContactFlags (
			OwnerPlayerID TEXT NOT NULL,
			PhoneNumber TEXT NOT NULL,
			IsFavorite INTEGER NOT NULL DEFAULT 0,
			IsBlocked INTEGER NOT NULL DEFAULT 0,
			UpdatedAt INTEGER NOT NULL,
			PRIMARY KEY (OwnerPlayerID, PhoneNumber)
		)
	]])

	EnsureTable("PhoneSmsReceipts", [[
		CREATE TABLE IF NOT EXISTS PhoneSmsReceipts (
			MessageID TEXT PRIMARY KEY,
			SenderPlayerID TEXT NOT NULL,
			RecipientPlayerID TEXT NOT NULL,
			SenderConversationID TEXT NOT NULL,
			RecipientConversationID TEXT NOT NULL,
			Status TEXT NOT NULL DEFAULT 'sent',
			CreatedAt INTEGER NOT NULL,
			DeliveredAt INTEGER NOT NULL DEFAULT 0,
			ReadAt INTEGER NOT NULL DEFAULT 0
		)
	]])

	EnsureTable("PhoneCallHistory", [[
		CREATE TABLE IF NOT EXISTS PhoneCallHistory (
			CallID TEXT NOT NULL,
			OwnerPlayerID TEXT NOT NULL,
			PeerPhoneNumber TEXT NOT NULL,
			PeerDisplayName TEXT NOT NULL DEFAULT '',
			Direction TEXT NOT NULL,
			Status TEXT NOT NULL,
			StartedAt INTEGER NOT NULL,
			AnsweredAt INTEGER NOT NULL DEFAULT 0,
			EndedAt INTEGER NOT NULL DEFAULT 0,
			DurationSeconds INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (CallID, OwnerPlayerID)
		)
	]])

	EnsureTable("PhonePhotos", [[
		CREATE TABLE IF NOT EXISTS PhonePhotos (
			ID TEXT PRIMARY KEY,
			PlayerID TEXT NOT NULL,
			ImageUrl TEXT NOT NULL,
			StorageKey TEXT,
			Source TEXT NOT NULL DEFAULT 'camera',
			Width INTEGER NOT NULL DEFAULT 0,
			Height INTEGER NOT NULL DEFAULT 0,
			CreatedAt INTEGER NOT NULL
		)
	]])

	EnsureTable("PlayerDocuments", [[
		CREATE TABLE IF NOT EXISTS PlayerDocuments (
			ID TEXT PRIMARY KEY,
			DocumentType TEXT NOT NULL,
			DocumentNumber TEXT NOT NULL UNIQUE,
			HolderID TEXT NOT NULL,
			Status TEXT NOT NULL,
			IssuedAt INTEGER NOT NULL,
			ExpiresAt INTEGER NOT NULL DEFAULT 0,
			IssuedBy TEXT NOT NULL,
			PhotoUID TEXT NOT NULL DEFAULT '',
			PhotoURL TEXT NOT NULL DEFAULT '',
			PayloadJson TEXT NOT NULL DEFAULT '{}',
			IssueRequestID TEXT NOT NULL UNIQUE,
			ReplacedByID TEXT NOT NULL DEFAULT '',
			RevokedAt INTEGER NOT NULL DEFAULT 0,
			CreatedAt INTEGER NOT NULL,
			UpdatedAt INTEGER NOT NULL
		)
	]])

	EnsureTable("ParkingSessions", [[
		CREATE TABLE IF NOT EXISTS ParkingSessions (
			ID TEXT PRIMARY KEY,
			RequestID TEXT NOT NULL UNIQUE,
			PlayerID TEXT NOT NULL,
			CitizenID TEXT NOT NULL,
			ZoneID TEXT NOT NULL,
			ZoneLabel TEXT NOT NULL,
			Plate TEXT NOT NULL,
			StartsAt INTEGER NOT NULL,
			ExpiresAt INTEGER NOT NULL,
			Minutes INTEGER NOT NULL,
			BasePrice INTEGER NOT NULL,
			WeekendDiscount INTEGER NOT NULL DEFAULT 0,
			PeakFee INTEGER NOT NULL DEFAULT 0,
			TotalPrice INTEGER NOT NULL,
			Status TEXT NOT NULL DEFAULT 'active',
			CreatedAt INTEGER NOT NULL
		)
	]])

	-- =========================
	-- Indexes
	-- =========================
	TryExec("idx_phone_photos_player_created", [[
		CREATE INDEX IF NOT EXISTS idx_phone_photos_player_created
		ON PhonePhotos(PlayerID, CreatedAt DESC)
	]])

	TryExec("idx_player_documents_holder_type", [[
		CREATE INDEX IF NOT EXISTS idx_player_documents_holder_type
		ON PlayerDocuments(HolderID, DocumentType, Status)
	]])

	TryExec("idx_parking_sessions_player_expiry", [[
		CREATE INDEX IF NOT EXISTS idx_parking_sessions_player_expiry
		ON ParkingSessions(PlayerID, ExpiresAt DESC)
	]])

	TryExec("idx_parking_sessions_plate_expiry", [[
		CREATE INDEX IF NOT EXISTS idx_parking_sessions_plate_expiry
		ON ParkingSessions(Plate, ExpiresAt DESC)
	]])

	-- Chat indexes (NEW)
	TryExec("idx_chat_conv_owner_last", [[
		CREATE INDEX IF NOT EXISTS idx_chat_conv_owner_last
		ON ChatConversations(OwnerPid, LastMsgAt DESC)
	]])

	TryExec("idx_chat_msg_owner_conv_created", [[
		CREATE INDEX IF NOT EXISTS idx_chat_msg_owner_conv_created
		ON ChatMessages(OwnerPid, ConvId, CreatedAt DESC)
	]])

	TryExec("idx_phone_profiles_number", [[
		CREATE UNIQUE INDEX IF NOT EXISTS idx_phone_profiles_number
		ON PhoneProfiles(PhoneNumber)
	]])

	TryExec("idx_phone_contacts_owner_name", [[
		CREATE INDEX IF NOT EXISTS idx_phone_contacts_owner_name
		ON PhoneContacts(OwnerPlayerID, ContactName COLLATE NOCASE)
	]])

	if LegacyLocalDomainSchemaEnabled() then
	TryExec("idx_courier_jobs_player_status", [[
		CREATE INDEX IF NOT EXISTS idx_courier_jobs_player_status
		ON CourierJobs(PlayerID, Status)
	]])

	TryExec("idx_courier_jobs_status", [[
		CREATE INDEX IF NOT EXISTS idx_courier_jobs_status
		ON CourierJobs(Status)
	]])

	TryExec("idx_courier_invoices_player", [[
		CREATE INDEX IF NOT EXISTS idx_courier_invoices_player
		ON CourierInvoices(PlayerID, CreatedAt DESC)
	]])

	TryExec("idx_trucker_orders_status", [[
		CREATE INDEX IF NOT EXISTS idx_trucker_orders_status
		ON TruckerOrders(Status)
	]])

	TryExec("idx_trucker_orders_assigned", [[
		CREATE INDEX IF NOT EXISTS idx_trucker_orders_assigned
		ON TruckerOrders(AssignedPlayerID, Status)
	]])

	TryExec("idx_owned_shop_products_shop", [[
		CREATE INDEX IF NOT EXISTS idx_owned_shop_products_shop
		ON OwnedShopProducts(ShopID, Enabled)
	]])

	TryExec("idx_owned_shop_ledger_shop", [[
		CREATE INDEX IF NOT EXISTS idx_owned_shop_ledger_shop
		ON OwnedShopLedger(ShopID, CreatedAt DESC)
	]])

	TryExec("idx_owned_shop_tx_shop", [[
		CREATE INDEX IF NOT EXISTS idx_owned_shop_tx_shop
		ON OwnedShopTransactions(ShopID, CreatedAt DESC)
	]])

	TryExec("idx_shop_supply_orders_shop_status", [[
		CREATE INDEX IF NOT EXISTS idx_shop_supply_orders_shop_status
		ON ShopSupplyOrders(ShopID, Status)
	]])

	TryExec("idx_shop_supply_orders_trucker", [[
		CREATE INDEX IF NOT EXISTS idx_shop_supply_orders_trucker
		ON ShopSupplyOrders(TruckerOrderID)
	]])
	end

	LogSchema("schema done")
end

function DB.Init()
	if isReady then return true end

	Log("DB.Init called, isReady=" .. tostring(isReady))
	Log("using file: " .. tostring(DB_FILE))

	Database.Initialize(DB_FILE)

	TryExec("pragma_busy_timeout", [[PRAGMA busy_timeout = 2000]])
	TryExec("pragma_journal_mode", [[PRAGMA journal_mode = WAL]])
	TryExec("pragma_synchronous", [[PRAGMA synchronous = NORMAL]])

	DB.Schema()

	LogSchema("health Players=" .. tostring(TableExists("Players")))
	LogSchema("health ChatConversations=" .. tostring(TableExists("ChatConversations")))
	LogSchema("health ChatMessages=" .. tostring(TableExists("ChatMessages")))
	if LegacyLocalDomainSchemaEnabled() then
	LogSchema("health CourierProfiles=" .. tostring(TableExists("CourierProfiles")))
	LogSchema("health CourierJobs=" .. tostring(TableExists("CourierJobs")))
	LogSchema("health CourierInvoices=" .. tostring(TableExists("CourierInvoices")))
	LogSchema("health TruckerProfiles=" .. tostring(TableExists("TruckerProfiles")))
	LogSchema("health TruckerOrders=" .. tostring(TableExists("TruckerOrders")))
	LogSchema("health OwnedShops=" .. tostring(TableExists("OwnedShops")))
	LogSchema("health OwnedShopProducts=" .. tostring(TableExists("OwnedShopProducts")))
	LogSchema("health ShopSupplyOrders=" .. tostring(TableExists("ShopSupplyOrders")))
	end
	isReady = true
	Log("ready")
	return true
end

-- =========================
-- Players
-- =========================

function DB.GetPlayer(id)
	EnsureReady()
	local rows = Database.Select(
		"SELECT ID, Name, Cash, CreatedAt, LastSeen FROM Players WHERE ID = ?",
		{ tostring(id) }
	)

	return RowsFirst(rows)
end

function DB.UpsertPlayer(id, name, cash)
	local pid = tostring(id)
	local pname = tostring(name or "Unknown")
	local now = Now()

	local existing = DB.GetPlayer(pid)

	if not existing then
		Log("insert player: " .. pid .. " (" .. pname .. ") cash=" .. tostring(tonumber(cash) or 0))
		return Database.Execute(
			"INSERT INTO Players (ID, Name, Cash, CreatedAt, LastSeen) VALUES (?, ?, ?, ?, ?)",
			{ pid, pname, tonumber(cash) or 0, now, now }
		)
	end

	Log("update player: " .. pid .. " (" .. pname .. ") cash=" .. tostring(tonumber(cash) or tonumber(DB.RowGet(existing, "Cash")) or 0))
	return Database.Execute(
		"UPDATE Players SET Name = ?, Cash = ?, LastSeen = ? WHERE ID = ?",
		{ pname, tonumber(cash) or tonumber(DB.RowGet(existing, "Cash")) or 0, now, pid }
	)
end

function DB.SetPlayerCash(id, cash)
	local pid = tostring(id)
	local now = Now()

	Log("set cash: " .. pid .. " cash=" .. tostring(tonumber(cash) or 0))
	return Database.Execute(
		"UPDATE Players SET Cash = ?, LastSeen = ? WHERE ID = ?",
		{ tonumber(cash) or 0, now, pid }
	)
end

-- =========================
-- Settings
-- =========================

local SETTINGS_DEFAULTS = {
	language = "en",
	volume = 0.8,
	silentMode = false,
	vibration = true,
	doNotDisturb = false,
	allowFavoriteCalls = true,
	missedCallNotifications = true,

	setupCompleted = false,
	pinEnabled = false,
	pinCode = nil,
	faceIdEnabled = false,
	deviceName = "Union Device",

	-- Phone UI
	uiFrameScale = 1.0,
	uiOffsetX = 0.0,
	uiOffsetY = 0.0,
	uiEditMode = false,
}

local function EncodeHomeLayout(value)
	if type(value) ~= "table" then return "" end
	if json and type(json.encode) == "function" then
		local ok, encoded = pcall(json.encode, value)
		if ok and type(encoded) == "string" then return encoded end
	end
	return ""
end

local function DecodeHomeLayout(value)
	if type(value) ~= "string" or value == "" then return nil end
	if json and type(json.decode) == "function" then
		local ok, decoded = pcall(json.decode, value)
		if ok and type(decoded) == "table" then return decoded end
	end
	return nil
end


function DB.GetSettings(playerId)
	local pid = tostring(playerId)

	local rows = Database.Select([[
		SELECT
			PlayerID,
			Language,
			Volume,
			UpdatedAt,
			SetupCompleted,
			PinEnabled,
			PinCode,
			FaceIdEnabled,
			DeviceName,
			UIFrameScale,
			UIOffsetX,
			UIOffsetY,
			UIEditMode,
			SilentMode,
			Vibration,
			DoNotDisturb,
			AllowFavoriteCalls,
			MissedCallNotifications,
			HomeLayoutJson,
			TabletLayoutJson
		FROM PlayerSettings
		WHERE PlayerID = ?
	]], { pid })

	local r = RowsFirst(rows)

	if r then
		return {
			language = tostring(DB.RowGet(r, "Language") or SETTINGS_DEFAULTS.language),
			volume = tonumber(DB.RowGet(r, "Volume") or SETTINGS_DEFAULTS.volume),
			silentMode = (tonumber(DB.RowGet(r, "SilentMode") or 0) == 1),
			vibration = (tonumber(DB.RowGet(r, "Vibration") or 1) == 1),
			doNotDisturb = (tonumber(DB.RowGet(r, "DoNotDisturb") or 0) == 1),
			allowFavoriteCalls = (tonumber(DB.RowGet(r, "AllowFavoriteCalls") or 1) == 1),
			missedCallNotifications = (tonumber(DB.RowGet(r, "MissedCallNotifications") or 1) == 1),
			homeLayout = DecodeHomeLayout(DB.RowGet(r, "HomeLayoutJson")),
			tabletLayout = DecodeHomeLayout(DB.RowGet(r, "TabletLayoutJson")),
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0),

			setupCompleted = (tonumber(DB.RowGet(r, "SetupCompleted") or 0) == 1),
			pinEnabled = (tonumber(DB.RowGet(r, "PinEnabled") or 0) == 1),
			pinCode = DB.RowGet(r, "PinCode"),
			faceIdEnabled = (tonumber(DB.RowGet(r, "FaceIdEnabled") or 0) == 1),
			deviceName = tostring(DB.RowGet(r, "DeviceName") or SETTINGS_DEFAULTS.deviceName),

			ui = {
				frameScale = tonumber(DB.RowGet(r, "UIFrameScale") or SETTINGS_DEFAULTS.uiFrameScale),
				offsetX = tonumber(DB.RowGet(r, "UIOffsetX") or SETTINGS_DEFAULTS.uiOffsetX),
				offsetY = tonumber(DB.RowGet(r, "UIOffsetY") or SETTINGS_DEFAULTS.uiOffsetY),
				editMode = (tonumber(DB.RowGet(r, "UIEditMode") or 0) == 1),
			}
		}
	end

	return nil
end

function DB.UpsertSettings(playerId, settings)
	local pid = tostring(playerId)
	local now = Now()

	local existing = DB.GetSettings(pid)

	-- defaults
	local lang = existing and existing.language or "en"
	local vol = existing and existing.volume or 0.8
	local silentMode = existing and existing.silentMode == true or false
	local vibration = not existing or existing.vibration ~= false
	local doNotDisturb = existing and existing.doNotDisturb == true or false
	local allowFavoriteCalls = not existing or existing.allowFavoriteCalls ~= false
	local missedCallNotifications = not existing or existing.missedCallNotifications ~= false
	local homeLayout = existing and existing.homeLayout or nil
	local tabletLayout = existing and existing.tabletLayout or nil

	local setupCompleted = existing and (existing.setupCompleted == true) or false
	local pinEnabled = existing and (existing.pinEnabled == true) or false
	local pinCode = existing and existing.pinCode or nil
	local faceIdEnabled = existing and (existing.faceIdEnabled == true) or false
	local deviceName = existing and existing.deviceName or SETTINGS_DEFAULTS.deviceName

	local uiFrameScale = existing and existing.ui and existing.ui.frameScale or SETTINGS_DEFAULTS.uiFrameScale
	local uiOffsetX = existing and existing.ui and existing.ui.offsetX or SETTINGS_DEFAULTS.uiOffsetX
	local uiOffsetY = existing and existing.ui and existing.ui.offsetY or SETTINGS_DEFAULTS.uiOffsetY
	local uiEditMode = existing and existing.ui and (existing.ui.editMode == true) or SETTINGS_DEFAULTS.uiEditMode


	-- apply payload
	if type(settings) == "table" then
		if settings.language ~= nil then lang = tostring(settings.language) end
		if settings.volume ~= nil then vol = tonumber(settings.volume) or vol end
		if settings.silentMode ~= nil then silentMode = settings.silentMode == true end
		if settings.vibration ~= nil then vibration = settings.vibration == true end
		if settings.doNotDisturb ~= nil then doNotDisturb = settings.doNotDisturb == true end
		if settings.allowFavoriteCalls ~= nil then allowFavoriteCalls = settings.allowFavoriteCalls == true end
		if settings.missedCallNotifications ~= nil then missedCallNotifications = settings.missedCallNotifications == true end
		if type(settings.homeLayout) == "table" then homeLayout = settings.homeLayout end
		if type(settings.tabletLayout) == "table" then tabletLayout = settings.tabletLayout end

		local uiIn = type(settings.ui) == "table" and settings.ui or {}

		if uiIn.frameScale ~= nil then uiFrameScale = tonumber(uiIn.frameScale) or uiFrameScale end
		if uiIn.offsetX ~= nil then uiOffsetX = tonumber(uiIn.offsetX) or uiOffsetX end
		if uiIn.offsetY ~= nil then uiOffsetY = tonumber(uiIn.offsetY) or uiOffsetY end
		if uiIn.editMode ~= nil then uiEditMode = uiIn.editMode == true end

		if settings.setupCompleted ~= nil then setupCompleted = settings.setupCompleted == true end
		if settings.pinEnabled ~= nil then pinEnabled = settings.pinEnabled == true end
		if settings.pinCode ~= nil then
			local v = tostring(settings.pinCode or "")
			pinCode = (v ~= "" and v) or nil
		end

		if settings.faceIdEnabled ~= nil then faceIdEnabled = settings.faceIdEnabled == true end
		if settings.deviceName ~= nil then
			local v = tostring(settings.deviceName or "")
			if v ~= "" then deviceName = v end
		end
	end

	if faceIdEnabled then
		pinEnabled = false
	end

	local function VerifySaved(expectedResult)
		if expectedResult ~= true then return false end
		local saved = DB.GetSettings(pid)
		if not saved then
			Log("settings verification failed: row missing for " .. pid)
			return false
		end
		local verified = saved.setupCompleted == setupCompleted
			and saved.pinEnabled == pinEnabled
			and saved.faceIdEnabled == faceIdEnabled
			and saved.language == lang
			and saved.silentMode == silentMode
			and saved.vibration == vibration
			and saved.doNotDisturb == doNotDisturb
			and saved.allowFavoriteCalls == allowFavoriteCalls
			and saved.missedCallNotifications == missedCallNotifications
		if not verified then
			Log(("settings verification mismatch: %s setup=%s/%s pin=%s/%s face=%s/%s lang=%s/%s"):format(
				pid,
				tostring(saved.setupCompleted), tostring(setupCompleted),
				tostring(saved.pinEnabled), tostring(pinEnabled),
				tostring(saved.faceIdEnabled), tostring(faceIdEnabled),
				tostring(saved.language), tostring(lang)
			))
		end
		return verified
	end


	if not existing then
		Log(("insert settings: %s lang=%s volume=%s"):format(pid, tostring(lang), tostring(vol)))
		local ok = Database.Execute([[
			INSERT INTO PlayerSettings (
				PlayerID, Language, Volume, UpdatedAt,
				SetupCompleted, PinEnabled, PinCode, FaceIdEnabled, DeviceName,
				UIFrameScale, UIOffsetX, UIOffsetY, UIEditMode,
				SilentMode, Vibration, DoNotDisturb, AllowFavoriteCalls, MissedCallNotifications
				, HomeLayoutJson, TabletLayoutJson
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		]], {
			pid, lang, vol, now,
			setupCompleted and 1 or 0,
			pinEnabled and 1 or 0,
			pinCode or "",
			faceIdEnabled and 1 or 0,
			deviceName,

			uiFrameScale,
			uiOffsetX,
			uiOffsetY,
			uiEditMode and 1 or 0,
			silentMode and 1 or 0,
			vibration and 1 or 0,
			doNotDisturb and 1 or 0,
			allowFavoriteCalls and 1 or 0,
			missedCallNotifications and 1 or 0,
			EncodeHomeLayout(homeLayout),
			EncodeHomeLayout(tabletLayout)
		})
		Log(("settings insert result: %s setupCompleted=%s"):format(tostring(ok), tostring(setupCompleted)))
		return VerifySaved(ok)

	end

	Log(("update settings: %s lang=%s volume=%s"):format(pid, tostring(lang), tostring(vol)))
	local ok = Database.Execute([[
		UPDATE PlayerSettings SET
			Language = ?,
			Volume = ?,
			UpdatedAt = ?,
			SetupCompleted = ?,
			PinEnabled = ?,
			PinCode = ?,
			FaceIdEnabled = ?,
			DeviceName = ?,

			UIFrameScale = ?,
			UIOffsetX = ?,
			UIOffsetY = ?,
			UIEditMode = ?,
			SilentMode = ?,
			Vibration = ?,
			DoNotDisturb = ?,
			AllowFavoriteCalls = ?,
			MissedCallNotifications = ?
			, HomeLayoutJson = ?
			, TabletLayoutJson = ?
		WHERE PlayerID = ?
	]], {
		lang,
		vol,
		now,
		setupCompleted and 1 or 0,
		pinEnabled and 1 or 0,
		pinCode or "",
		faceIdEnabled and 1 or 0,
		deviceName,

		uiFrameScale,
		uiOffsetX,
		uiOffsetY,
		uiEditMode and 1 or 0,
		silentMode and 1 or 0,
		vibration and 1 or 0,
		doNotDisturb and 1 or 0,
		allowFavoriteCalls and 1 or 0,
		missedCallNotifications and 1 or 0,
		EncodeHomeLayout(homeLayout),
		EncodeHomeLayout(tabletLayout),

		pid
	})
	Log(("settings update result: %s setupCompleted=%s"):format(tostring(ok), tostring(setupCompleted)))
	return VerifySaved(ok)

end


function DB.EnsureSettings(playerId, defaults)
	local pid = tostring(playerId)

	local s = DB.GetSettings(pid)
	if s then return s end

	DB.UpsertSettings(pid, defaults or { language = "en", volume = 0.8 })
	return DB.GetSettings(pid) or (defaults or { language = "en", volume = 0.8 })
end

function DB.ResetSettingsFactory(playerId)
	local pid = tostring(playerId)
	local now = Now()

	-- ensure row exists
	DB.EnsureSettings(pid, SETTINGS_DEFAULTS)

	Log(("factory reset settings: %s"):format(pid))

	local ok = Database.Execute([[
		UPDATE PlayerSettings SET
			Language = ?,
			Volume = ?,
			UpdatedAt = ?,
			SetupCompleted = ?,
			PinEnabled = ?,
			PinCode = ?,
			FaceIdEnabled = ?,
			DeviceName = ?,

			UIFrameScale = ?,
			UIOffsetX = ?,
			UIOffsetY = ?,
			UIEditMode = ?,
			SilentMode = ?,
			Vibration = ?,
			DoNotDisturb = ?,
			AllowFavoriteCalls = ?,
			MissedCallNotifications = ?
			, HomeLayoutJson = ?
			, TabletLayoutJson = ?
		WHERE PlayerID = ?
	]], {
		SETTINGS_DEFAULTS.language,
		SETTINGS_DEFAULTS.volume,
		now,
		SETTINGS_DEFAULTS.setupCompleted and 1 or 0,
		SETTINGS_DEFAULTS.pinEnabled and 1 or 0,
		SETTINGS_DEFAULTS.pinCode or "",
		SETTINGS_DEFAULTS.faceIdEnabled and 1 or 0,
		SETTINGS_DEFAULTS.deviceName,

		SETTINGS_DEFAULTS.uiFrameScale,
		SETTINGS_DEFAULTS.uiOffsetX,
		SETTINGS_DEFAULTS.uiOffsetY,
		SETTINGS_DEFAULTS.uiEditMode and 1 or 0,
		SETTINGS_DEFAULTS.silentMode and 1 or 0,
		SETTINGS_DEFAULTS.vibration and 1 or 0,
		SETTINGS_DEFAULTS.doNotDisturb and 1 or 0,
		SETTINGS_DEFAULTS.allowFavoriteCalls and 1 or 0,
		SETTINGS_DEFAULTS.missedCallNotifications and 1 or 0,
		"",
		"",

		pid
	})
	if ok ~= true then return false end
	local saved = DB.GetSettings(pid)
	return saved ~= nil
		and saved.setupCompleted == false
		and saved.pinEnabled == false
		and saved.faceIdEnabled == false
		and saved.language == SETTINGS_DEFAULTS.language
end



--[=[
-- =========================
-- Legacy domain implementations moved to db/*.lua
-- =========================

function DB.GetShopProducts(id)
	local key = tostring(id or "default")

	local rows = Database.Select(
		"SELECT ID, Json, UpdatedAt FROM ShopProducts WHERE ID = ?",
		{ key }
	)

	return RowsFirst(rows)
end

function DB.UpsertShopProducts(id, jsonString)
	local key = tostring(id or "default")
	local now = Now()
	local jsonStr = tostring(jsonString or "[]")

	local existing = DB.GetShopProducts(key)

	if not existing then
		Log("insert shop products: " .. key .. " bytes=" .. tostring(#jsonStr))
		return Database.Execute(
			"INSERT INTO ShopProducts (ID, Json, UpdatedAt) VALUES (?, ?, ?)",
			{ key, jsonStr, now }
		)
	end

	Log("update shop products: " .. key .. " bytes=" .. tostring(#jsonStr))
	return Database.Execute(
		"UPDATE ShopProducts SET Json = ?, UpdatedAt = ? WHERE ID = ?",
		{ jsonStr, now, key }
	)
end

-- =========================
-- Owned shops
-- =========================

DB.Shops = DB.Shops or {}

local function PriceToPence(value)
	return math.floor((tonumber(value) or 0) * 100 + 0.5)
end

local function PenceToPrice(value)
	return (tonumber(value) or 0) / 100
end

local function SafeJsonEncode(value)
	if json and type(json.encode) == "function" then
		local ok, encoded = pcall(function()
			return json.encode(value)
		end)
		if ok and encoded then return tostring(encoded) end
	end

	return "{}"
end

local function MakeShopTxId(prefix, shopId)
	return ("%s|%s|%s|%s"):format(
		tostring(prefix or "shop"),
		tostring(shopId or "default"),
		tostring(NowMs()),
		tostring(math.random(1000, 9999))
	)
end

local function ShopCoordsToString(coords)
	if type(coords) == "string" then return coords end
	if type(coords) == "table" then
		return ("%s %s %s"):format(
			tostring(coords.X or coords.x or 0),
			tostring(coords.Y or coords.y or 0),
			tostring(coords.Z or coords.z or 0)
		)
	end
	if type(coords) == "userdata" then
		local okX, x = pcall(function() return coords.X end)
		local okY, y = pcall(function() return coords.Y end)
		local okZ, z = pcall(function() return coords.Z end)
		return ("%s %s %s"):format(
			tostring(okX and x or 0),
			tostring(okY and y or 0),
			tostring(okZ and z or 0)
		)
	end
	return tostring(coords or "")
end

function DB.Shops.Get(shopId)
	EnsureReady()

	local rows = Database.Select([[
		SELECT ID, Label, Type, Status, OwnerID, BusinessPrice, Balance, TodaySales, StockValue, Coords, CreatedAt, UpdatedAt
		FROM OwnedShops
		WHERE ID = ?
	]], { tostring(shopId or "") })

	return RowsFirst(rows)
end

function DB.Shops.CountOwnedByOwner(ownerId)
	EnsureReady()

	local oid = tostring(ownerId or "")
	if oid == "" then return 0 end

	local rows = Database.Select([[
		SELECT COUNT(*) AS CountValue
		FROM OwnedShops
		WHERE OwnerID = ?
	]], { oid })

	local row = RowsFirst(rows)
	return tonumber(DB.RowGet(row, "CountValue") or DB.RowGet(row, "count") or 0) or 0
end

function DB.Shops.SeedFromConfig(locations)
	EnsureReady()

	if type(locations) ~= "table" then return true end

	local now = Now()

	for id, shop in pairs(locations) do
		if type(shop) == "table" then
			local shopId = tostring(shop.id or id)
			local existing = DB.Shops.Get(shopId)
			local label = tostring(shop.label or shopId)
			local shopType = tostring(shop.type or "default")
			local status = tostring(shop.status or "setup")
			local coords = ShopCoordsToString(shop.coords)
			local businessPrice = PriceToPence(shop.businessPrice)

			if not existing then
				Database.Execute([[
					INSERT INTO OwnedShops (
						ID, Label, Type, Status, OwnerID, BusinessPrice, Balance, TodaySales, StockValue, Coords, CreatedAt, UpdatedAt
					) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				]], {
					shopId,
					label,
					shopType,
					status,
					nil,
					businessPrice,
					tonumber(shop.balance) or 0,
					tonumber(shop.todaySales) or 0,
					tonumber(shop.stockValue) or 0,
					coords,
					now,
					now,
				})
			else
				Database.Execute([[
					UPDATE OwnedShops
					SET Label = ?, Type = ?, BusinessPrice = ?, Coords = ?, UpdatedAt = ?
					WHERE ID = ?
				]], { label, shopType, businessPrice, coords, now, shopId })
			end

			for _, product in ipairs(shop.products or {}) do
				local productId = tostring(product.id or product.name or "")
				if productId ~= "" then
					local productRows = Database.Select([[
						SELECT ShopID, ProductID
						FROM OwnedShopProducts
						WHERE ShopID = ? AND ProductID = ?
					]], { shopId, productId })

					local productExisting = RowsFirst(productRows)
					local productLabel = tostring(product.name or product.label or productId)
					local category = tostring(product.category or "General")
					local pricePence = PriceToPence(product.price)
					local maxStock = math.max(1, math.floor(tonumber(product.maxStock) or 100))
					local maxOrderQty = math.max(1, math.floor(tonumber(product.maxOrderQty) or math.min(maxStock, 25)))
					local stock = product.stock ~= nil
						and math.max(0, math.floor(tonumber(product.stock) or 0))
						or math.max(0, math.floor(tonumber(product.defaultStock or maxStock) or maxStock))

					if not productExisting then
						Database.Execute([[
							INSERT INTO OwnedShopProducts (
								ShopID, ProductID, Label, Category, PricePence, Stock, MaxStock, MaxOrderQty, Enabled, UpdatedAt
							) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
						]], {
							shopId,
							productId,
							productLabel,
							category,
							pricePence,
							stock,
							maxStock,
							maxOrderQty,
							product.enabled == false and 0 or 1,
							now,
						})
					else
						Database.Execute([[
							UPDATE OwnedShopProducts
							SET Label = ?, Category = ?, PricePence = ?, MaxStock = ?, MaxOrderQty = ?, UpdatedAt = ?
							WHERE ShopID = ? AND ProductID = ?
						]], {
							productLabel,
							category,
							pricePence,
							maxStock,
							maxOrderQty,
							now,
							shopId,
							productId,
						})
					end
				end
			end
		end
	end

	return true
end

function DB.Shops.Claim(shopId, ownerId)
	EnsureReady()

	local sid = tostring(shopId or "")
	local oid = tostring(ownerId or "")
	if sid == "" or oid == "" then return false, "invalid_payload" end

	if DB.Shops.CountOwnedByOwner(oid) > 0 then
		return false, "player_already_owns_business"
	end

	local row = DB.Shops.Get(sid)
	if not row then return false, "shop_not_found" end

	local currentOwner = DB.RowGet(row, "OwnerID")
	currentOwner = currentOwner ~= nil and tostring(currentOwner) or ""
	if currentOwner ~= "" then
		return false, "shop_already_owned"
	end

	local now = Now()
	local ok = Database.Execute([[
		UPDATE OwnedShops
		SET OwnerID = ?, Status = 'active', UpdatedAt = ?
		WHERE ID = ? AND (OwnerID IS NULL OR OwnerID = '')
	]], { oid, now, sid })

	if not ok then return false, "claim_failed" end

	local claimed = DB.Shops.Get(sid)
	local claimedOwner = claimed and DB.RowGet(claimed, "OwnerID") or nil
	if tostring(claimedOwner or "") ~= oid then
		return false, "shop_already_owned"
	end

	Database.Execute([[
		INSERT INTO OwnedShopLedger (ID, ShopID, Amount, Type, Reason, MetaJson, CreatedAt)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	]], {
		MakeShopTxId("claim", sid),
		sid,
		0,
		"claim",
		"business_claimed",
		SafeJsonEncode({ ownerId = oid }),
		now,
	})

	return true, "ok", {
		shopId = sid,
		ownerId = oid,
		businessPrice = tonumber(DB.RowGet(claimed, "BusinessPrice") or 0) or 0,
	}
end

function DB.Shops.ListProducts(shopId, onlyEnabled)
	EnsureReady()

	local rows = Database.Select([[
		SELECT ShopID, ProductID, Label, Category, PricePence, Stock, MaxStock, MaxOrderQty, Enabled, UpdatedAt
		FROM OwnedShopProducts
		WHERE ShopID = ?
		ORDER BY Category ASC, Label ASC
	]], { tostring(shopId or "") })

	local out = {}
	local count = RowsCount(rows)

	for i = 1, count do
		local row = RowAt(rows, i)
		local enabled = tonumber(DB.RowGet(row, "Enabled") or 0) == 1
		if not onlyEnabled or enabled then
			out[#out + 1] = {
				id = tostring(DB.RowGet(row, "ProductID") or ""),
				label = tostring(DB.RowGet(row, "Label") or DB.RowGet(row, "ProductID") or "Item"),
				name = tostring(DB.RowGet(row, "Label") or DB.RowGet(row, "ProductID") or "Item"),
				category = tostring(DB.RowGet(row, "Category") or "General"),
				description = "",
				image = tostring(DB.RowGet(row, "ProductID") or ""),
				price = PenceToPrice(DB.RowGet(row, "PricePence")),
				pricePence = tonumber(DB.RowGet(row, "PricePence") or 0),
				stock = tonumber(DB.RowGet(row, "Stock") or 0),
				maxStock = tonumber(DB.RowGet(row, "MaxStock") or 0),
				maxOrderQty = tonumber(DB.RowGet(row, "MaxOrderQty") or 25),
				enabled = enabled,
			}
		end
	end

	return out
end

function DB.Shops.GetProduct(shopId, productId)
	EnsureReady()

	local rows = Database.Select([[
		SELECT ShopID, ProductID, Label, Category, PricePence, Stock, MaxStock, MaxOrderQty, Enabled, UpdatedAt
		FROM OwnedShopProducts
		WHERE ShopID = ? AND ProductID = ?
	]], { tostring(shopId or ""), tostring(productId or "") })

	return RowsFirst(rows)
end

function DB.Shops.TryTakeStock(shopId, productId, qty)
	EnsureReady()

	local sid = tostring(shopId or "")
	local pid = tostring(productId or "")
	local amount = math.floor(tonumber(qty) or 0)
	if sid == "" or pid == "" or amount <= 0 then
		return false, "invalid_stock_request"
	end

	local row = DB.Shops.GetProduct(sid, pid)
	if not row then return false, "item_not_found" end
	if tonumber(DB.RowGet(row, "Enabled") or 0) ~= 1 then return false, "item_disabled" end

	local stock = tonumber(DB.RowGet(row, "Stock") or 0)
	if stock < amount then
		return false, "not_enough_stock", { stock = stock, requested = amount }
	end

	local ok = Database.Execute([[
		UPDATE OwnedShopProducts
		SET Stock = Stock - ?, UpdatedAt = ?
		WHERE ShopID = ? AND ProductID = ? AND Stock >= ? AND Enabled = 1
	]], { amount, Now(), sid, pid, amount })

	if not ok then return false, "stock_update_failed" end
	return true, "ok"
end

function DB.Shops.AddStock(shopId, productId, qty)
	EnsureReady()

	local amount = math.floor(tonumber(qty) or 0)
	if amount <= 0 then return false end

	return Database.Execute([[
		UPDATE OwnedShopProducts
		SET Stock = MIN(MaxStock, Stock + ?), UpdatedAt = ?
		WHERE ShopID = ? AND ProductID = ?
	]], { amount, Now(), tostring(shopId or ""), tostring(productId or "") })
end

function DB.Shops.SetProductPrice(shopId, productId, pricePence)
	EnsureReady()

	local sid = tostring(shopId or "")
	local pid = tostring(productId or "")
	local price = ToInt(pricePence)
	if sid == "" or pid == "" or price < 0 then return false, "invalid_price" end

	local row = DB.Shops.GetProduct(sid, pid)
	if not row then return false, "item_not_found" end

	local ok = Database.Execute([[
		UPDATE OwnedShopProducts
		SET PricePence = ?, UpdatedAt = ?
		WHERE ShopID = ? AND ProductID = ?
	]], { price, Now(), sid, pid })

	return ok == true, ok and "ok" or "price_update_failed"
end

function DB.Shops.RestockProduct(shopId, productId, qty)
	EnsureReady()

	local sid = tostring(shopId or "")
	local pid = tostring(productId or "")
	local amount = math.floor(tonumber(qty) or 0)
	if sid == "" or pid == "" or amount <= 0 then return false, "invalid_restock" end

	local row = DB.Shops.GetProduct(sid, pid)
	if not row then return false, "item_not_found" end

	local stock = tonumber(DB.RowGet(row, "Stock") or 0)
	local maxStock = tonumber(DB.RowGet(row, "MaxStock") or 0)
	local added = math.min(amount, math.max(0, maxStock - stock))

	if added <= 0 then
		return false, "stock_full", { stock = stock, maxStock = maxStock }
	end

	local ok = Database.Execute([[
		UPDATE OwnedShopProducts
		SET Stock = Stock + ?, UpdatedAt = ?
		WHERE ShopID = ? AND ProductID = ?
	]], { added, Now(), sid, pid })

	return ok == true, ok and "ok" or "restock_failed", { added = added, stock = stock + added, maxStock = maxStock }
end

function DB.Shops.WithdrawBalance(shopId, amountPence)
	EnsureReady()

	local sid = tostring(shopId or "")
	local amount = ToInt(amountPence)
	if sid == "" or amount <= 0 then return false, "invalid_amount" end

	local row = DB.Shops.Get(sid)
	if not row then return false, "shop_not_found" end

	local balance = tonumber(DB.RowGet(row, "Balance") or 0)
	if balance < amount then
		return false, "not_enough_shop_balance", { balance = balance, requested = amount }
	end

	local ok = Database.Execute([[
		UPDATE OwnedShops
		SET Balance = Balance - ?, UpdatedAt = ?
		WHERE ID = ? AND Balance >= ?
	]], { amount, Now(), sid, amount })

	if not ok then return false, "withdraw_failed" end

	Database.Execute([[
		INSERT INTO OwnedShopLedger (ID, ShopID, Amount, Type, Reason, MetaJson, CreatedAt)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	]], {
		MakeShopTxId("withdraw", sid),
		sid,
		-amount,
		"debit",
		"owner_withdraw",
		SafeJsonEncode({ amountPence = amount }),
		Now(),
	})

	return true, "ok", { amount = amount, balanceAfter = balance - amount }
end

function DB.Shops.RollbackWithdraw(shopId, amountPence, reason, meta)
	EnsureReady()

	local sid = tostring(shopId or "")
	local amount = ToInt(amountPence)
	if sid == "" or amount <= 0 then return false end

	local now = Now()
	local ok = Database.Execute([[
		UPDATE OwnedShops
		SET Balance = Balance + ?, UpdatedAt = ?
		WHERE ID = ?
	]], { amount, now, sid })

	if not ok then return false end

	return Database.Execute([[
		INSERT INTO OwnedShopLedger (ID, ShopID, Amount, Type, Reason, MetaJson, CreatedAt)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	]], {
		MakeShopTxId("withdraw_rollback", sid),
		sid,
		amount,
		"credit",
		tostring(reason or "withdraw_rollback"),
		SafeJsonEncode(meta or {}),
		now,
	})
end

function DB.Shops.DebitBalance(shopId, amountPence, reason, meta)
	EnsureReady()

	local sid = tostring(shopId or "")
	local amount = ToInt(amountPence)
	if sid == "" or amount <= 0 then return false, "invalid_amount" end

	local row = DB.Shops.Get(sid)
	if not row then return false, "shop_not_found" end

	local balance = tonumber(DB.RowGet(row, "Balance") or 0) or 0
	if balance < amount then
		return false, "not_enough_shop_balance", { balance = balance, requested = amount }
	end

	local now = Now()
	local ok = Database.Execute([[
		UPDATE OwnedShops
		SET Balance = Balance - ?, UpdatedAt = ?
		WHERE ID = ? AND Balance >= ?
	]], { amount, now, sid, amount })

	if not ok then return false, "shop_debit_failed" end

	Database.Execute([[
		INSERT INTO OwnedShopLedger (ID, ShopID, Amount, Type, Reason, MetaJson, CreatedAt)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	]], {
		MakeShopTxId("debit", sid),
		sid,
		-amount,
		"debit",
		tostring(reason or "shop_debit"),
		SafeJsonEncode(meta or {}),
		now,
	})

	return true, "ok", { amount = amount, balanceAfter = balance - amount }
end

function DB.Shops.CreditBalance(shopId, amountPence, reason, meta)
	EnsureReady()

	local sid = tostring(shopId or "")
	local amount = ToInt(amountPence)
	local now = Now()
	if sid == "" or amount == 0 then return false end

	local ok = Database.Execute([[
		UPDATE OwnedShops
		SET Balance = Balance + ?, TodaySales = TodaySales + ?, UpdatedAt = ?
		WHERE ID = ?
	]], { amount, amount > 0 and amount or 0, now, sid })

	if not ok then return false end

	return Database.Execute([[
		INSERT INTO OwnedShopLedger (ID, ShopID, Amount, Type, Reason, MetaJson, CreatedAt)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	]], {
		MakeShopTxId("ledger", sid),
		sid,
		amount,
		amount >= 0 and "credit" or "debit",
		tostring(reason or ""),
		SafeJsonEncode(meta or {}),
		now,
	})
end

function DB.Shops.CreateSupplyOrder(data)
	EnsureReady()

	data = type(data) == "table" and data or {}
	local shopId = tostring(data.shopId or "")
	local productId = tostring(data.productId or "")
	local qty = math.floor(tonumber(data.qty) or 0)
	if shopId == "" or productId == "" or qty <= 0 then
		return false, "invalid_supply_order"
	end

	local now = Now()
	local id = tostring(data.id or MakeShopTxId("supply", shopId))

	local ok = Database.Execute([[
		INSERT INTO ShopSupplyOrders (
			ID, ShopID, ProductID, Qty, GoodsCostPence, DriverFeePence, TotalCostPence,
			TruckerOrderID, Status, CreatedBy, MetaJson, CreatedAt, UpdatedAt, DeliveredAt
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	]], {
		id,
		shopId,
		productId,
		qty,
		ToInt(data.goodsCostPence),
		ToInt(data.driverFeePence),
		ToInt(data.totalCostPence),
		tostring(data.truckerOrderId or ""),
		tostring(data.status or "pending_trucker"),
		tostring(data.createdBy or ""),
		SafeJsonEncode(data.meta or {}),
		now,
		now,
		0,
	})

	if not ok then return false, "supply_order_insert_failed" end
	return true, "ok", { id = id }
end

function DB.Shops.SetSupplyOrderTruckerOrder(supplyOrderId, truckerOrderId)
	EnsureReady()

	local supplyId = tostring(supplyOrderId or "")
	local orderId = tostring(truckerOrderId or "")
	if supplyId == "" or orderId == "" then return false, "invalid_supply_link" end

	local ok = Database.Execute([[
		UPDATE ShopSupplyOrders
		SET TruckerOrderID = ?, Status = 'pending_delivery', UpdatedAt = ?
		WHERE ID = ?
	]], { orderId, Now(), supplyId })

	return ok == true, ok and "ok" or "supply_link_failed"
end

function DB.Shops.MarkSupplyDeliveredByTruckerOrder(truckerOrderId)
	EnsureReady()

	local orderId = tostring(truckerOrderId or "")
	if orderId == "" then return false, "invalid_trucker_order" end

	local rows = Database.Select([[
		SELECT *
		FROM ShopSupplyOrders
		WHERE TruckerOrderID = ?
		  AND Status != 'delivered'
		LIMIT 1
	]], { orderId })

	local row = RowsFirst(rows)
	if not row then return false, "supply_order_not_found" end

	local shopId = tostring(DB.RowGet(row, "ShopID") or "")
	local productId = tostring(DB.RowGet(row, "ProductID") or "")
	local qty = math.floor(tonumber(DB.RowGet(row, "Qty") or 0) or 0)
	if shopId == "" or productId == "" or qty <= 0 then
		return false, "invalid_supply_order"
	end

	local okStock = DB.Shops.AddStock(shopId, productId, qty)
	if not okStock then return false, "stock_add_failed" end

	local now = Now()
	local ok = Database.Execute([[
		UPDATE ShopSupplyOrders
		SET Status = 'delivered', DeliveredAt = ?, UpdatedAt = ?
		WHERE ID = ?
	]], {
		now,
		now,
		tostring(DB.RowGet(row, "ID") or ""),
	})

	return ok == true, ok and "ok" or "supply_deliver_failed", {
		shopId = shopId,
		productId = productId,
		qty = qty,
	}
end

function DB.Shops.InsertTransaction(data)
	EnsureReady()

	data = type(data) == "table" and data or {}
	local shopId = tostring(data.shopId or "")
	if shopId == "" then return false end

	return Database.Execute([[
		INSERT INTO OwnedShopTransactions (
			ID, ShopID, BuyerID, ItemsJson, SubtotalPence, VatPence, TotalPence, PaymentMethod, CreatedAt
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	]], {
		tostring(data.id or MakeShopTxId("tx", shopId)),
		shopId,
		tostring(data.buyerId or ""),
		SafeJsonEncode(data.items or {}),
		ToInt(data.subtotalPence),
		ToInt(data.vatPence),
		ToInt(data.totalPence),
		tostring(data.paymentMethod or "bank"),
		tonumber(data.createdAt) or Now(),
	})
end

function DB.Shops.ListManaged()
	EnsureReady()

	local rows = Database.Select([[
		SELECT ID, Label, Type, Status, OwnerID, BusinessPrice, Balance, TodaySales, StockValue, Coords, CreatedAt, UpdatedAt
		FROM OwnedShops
		ORDER BY Label ASC
	]])

	local out = {}
	local count = RowsCount(rows)

	for i = 1, count do
		local row = RowAt(rows, i)
		local shopId = tostring(DB.RowGet(row, "ID") or "")
		local ownerId = DB.RowGet(row, "OwnerID")
		local isOwned = ownerId ~= nil and tostring(ownerId) ~= ""
		local ownerName = ""
		if isOwned and DB.GetPlayer then
			local ownerRow = DB.GetPlayer(ownerId)
			ownerName = tostring(ownerRow and DB.RowGet(ownerRow, "Name") or "")
		end
		local products = DB.Shops.ListProducts(shopId, false)
		if not isOwned then
			for _, product in ipairs(products) do
				product.stock = product.maxStock
			end
		end

		out[#out + 1] = {
			id = shopId,
			label = tostring(DB.RowGet(row, "Label") or shopId),
			type = tostring(DB.RowGet(row, "Type") or "default"),
			status = tostring(DB.RowGet(row, "Status") or "setup"),
			ownerId = ownerId,
			ownerName = ownerName,
			owned = isOwned,
			forSale = not isOwned,
			businessPrice = PenceToPrice(DB.RowGet(row, "BusinessPrice")),
			businessPricePence = tonumber(DB.RowGet(row, "BusinessPrice") or 0),
			balance = PenceToPrice(DB.RowGet(row, "Balance")),
			todaySales = PenceToPrice(DB.RowGet(row, "TodaySales")),
			stockValue = PenceToPrice(DB.RowGet(row, "StockValue")),
			coords = tostring(DB.RowGet(row, "Coords") or ""),
			products = products,
		}
	end

	return out
end

-- =========================
-- Chat domain moved to db/chat.lua
-- =========================

-- =========================
-- Trucker
-- =========================

DB.Trucker = DB.Trucker or {}

function DB.Trucker.GetProfile(playerId)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return nil end

	local rows = Database.Select([[
		SELECT
			PlayerID,
			Name,
			Phone,
			Level,
			SkillsJson,
			UpdatedAt
		FROM TruckerProfiles
		WHERE PlayerID = ?
		LIMIT 1
	]], { pid })

	local r = RowsFirst(rows)
	if not r then return nil end

	return {
		playerId = tostring(DB.RowGet(r, "PlayerID") or pid),
		name = DB.RowGet(r, "Name"),
		phone = DB.RowGet(r, "Phone"),
		level = tonumber(DB.RowGet(r, "Level") or 1) or 1,
		skillsJson = DB.RowGet(r, "SkillsJson"),
		updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
	}
end

function DB.Trucker.EnsureProfile(playerId, defaults)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return nil end

	local existing = DB.Trucker.GetProfile(pid)
	if existing then return existing end

	defaults = type(defaults) == "table" and defaults or {}
	local now = Now()

	Database.Execute([[
		INSERT INTO TruckerProfiles (
			PlayerID, Name, Phone, Level, SkillsJson, UpdatedAt
		) VALUES (?, ?, ?, ?, ?, ?)
	]], {
		pid,
		tostring(defaults.name or "Driver"),
		tostring(defaults.phone or "N/A"),
		tonumber(defaults.level or 1) or 1,
		defaults.skillsJson ~= nil and tostring(defaults.skillsJson) or "[]",
		now
	})

	return DB.Trucker.GetProfile(pid)
end

function DB.Trucker.GetOrderById(orderId)
	EnsureReady()

	local id = tostring(orderId or "")
	if id == "" then return nil end

	local rows = Database.Select([[
		SELECT
			ID,
			AssignedPlayerID,
			Title,
			ClientName,
			CargoName,
			CargoClass,
			WeightKg,
			PickupLabel,
			DropoffLabel,
			DistanceKm,
			Reward,
			Deposit,
			VehicleClass,
			TrailerRequired,
			Status,
			EstimatedMinutes,
			DeadlineAt,
			Description,
			MinLevel,
			RequiredSkillsJson,
			IconImage,
			TruckImage,
			TrailerImage,
			CargoImage,
			CreatedAt,
			UpdatedAt
		FROM TruckerOrders
		WHERE ID = ?
		LIMIT 1
	]], { id })

	local r = RowsFirst(rows)
	if not r then return nil end

	return {
		id = tostring(DB.RowGet(r, "ID") or ""),
		assignedPlayerId = DB.RowGet(r, "AssignedPlayerID"),
		title = tostring(DB.RowGet(r, "Title") or ""),
		clientName = tostring(DB.RowGet(r, "ClientName") or ""),
		cargoName = tostring(DB.RowGet(r, "CargoName") or ""),
		cargoClass = tostring(DB.RowGet(r, "CargoClass") or "standard"),
		weightKg = tonumber(DB.RowGet(r, "WeightKg") or 0) or 0,
		pickupLabel = tostring(DB.RowGet(r, "PickupLabel") or ""),
		dropoffLabel = tostring(DB.RowGet(r, "DropoffLabel") or ""),
		distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
		reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
		deposit = tonumber(DB.RowGet(r, "Deposit") or 0) or 0,
		vehicleClass = DB.RowGet(r, "VehicleClass"),
		trailerRequired = (tonumber(DB.RowGet(r, "TrailerRequired") or 0) == 1),
		status = tostring(DB.RowGet(r, "Status") or "available"),
		estimatedMinutes = tonumber(DB.RowGet(r, "EstimatedMinutes") or 0) or 0,
		deadlineAt = tonumber(DB.RowGet(r, "DeadlineAt") or 0) or 0,
		description = DB.RowGet(r, "Description"),
		minLevel = tonumber(DB.RowGet(r, "MinLevel") or 1) or 1,
		requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
		iconImage = DB.RowGet(r, "IconImage"),
		truckImage = DB.RowGet(r, "TruckImage"),
		trailerImage = DB.RowGet(r, "TrailerImage"),
		cargoImage = DB.RowGet(r, "CargoImage"),
		createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
		updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
	}
end

function DB.Trucker.ListAvailableOrders(limit)
	EnsureReady()

	local lim = tonumber(limit) or 50

	local rows = Database.Select([[
		SELECT
			ID,
			AssignedPlayerID,
			Title,
			ClientName,
			CargoName,
			CargoClass,
			WeightKg,
			PickupLabel,
			DropoffLabel,
			DistanceKm,
			Reward,
			Deposit,
			VehicleClass,
			TrailerRequired,
			Status,
			EstimatedMinutes,
			DeadlineAt,
			Description,
			MinLevel,
			RequiredSkillsJson,
			IconImage,
			TruckImage,
			TrailerImage,
			CargoImage,
			CreatedAt,
			UpdatedAt
		FROM TruckerOrders
		WHERE Status = 'available'
		  AND (AssignedPlayerID IS NULL OR AssignedPlayerID = '')
		ORDER BY CreatedAt DESC
		LIMIT ?
	]], { lim })

	local out = {}
	local n = RowsCount(rows)

	for i = 1, n do
		local r = RowAt(rows, i)
		out[#out + 1] = {
			id = tostring(DB.RowGet(r, "ID") or ""),
			assignedPlayerId = DB.RowGet(r, "AssignedPlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			clientName = tostring(DB.RowGet(r, "ClientName") or ""),
			cargoName = tostring(DB.RowGet(r, "CargoName") or ""),
			cargoClass = tostring(DB.RowGet(r, "CargoClass") or "standard"),
			weightKg = tonumber(DB.RowGet(r, "WeightKg") or 0) or 0,
			pickupLabel = tostring(DB.RowGet(r, "PickupLabel") or ""),
			dropoffLabel = tostring(DB.RowGet(r, "DropoffLabel") or ""),
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			deposit = tonumber(DB.RowGet(r, "Deposit") or 0) or 0,
			vehicleClass = DB.RowGet(r, "VehicleClass"),
			trailerRequired = (tonumber(DB.RowGet(r, "TrailerRequired") or 0) == 1),
			status = tostring(DB.RowGet(r, "Status") or "available"),
			estimatedMinutes = tonumber(DB.RowGet(r, "EstimatedMinutes") or 0) or 0,
			deadlineAt = tonumber(DB.RowGet(r, "DeadlineAt") or 0) or 0,
			description = DB.RowGet(r, "Description"),
			minLevel = tonumber(DB.RowGet(r, "MinLevel") or 1) or 1,
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			iconImage = DB.RowGet(r, "IconImage"),
			truckImage = DB.RowGet(r, "TruckImage"),
			trailerImage = DB.RowGet(r, "TrailerImage"),
			cargoImage = DB.RowGet(r, "CargoImage"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		}
	end

	return out
end

function DB.Trucker.GetActiveOrder(playerId)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return nil end

	local rows = Database.Select([[
		SELECT
			ID,
			AssignedPlayerID,
			Title,
			ClientName,
			CargoName,
			CargoClass,
			WeightKg,
			PickupLabel,
			DropoffLabel,
			DistanceKm,
			Reward,
			Deposit,
			VehicleClass,
			TrailerRequired,
			Status,
			EstimatedMinutes,
			DeadlineAt,
			Description,
			MinLevel,
			RequiredSkillsJson,
			IconImage,
			TruckImage,
			TrailerImage,
			CargoImage,
			CreatedAt,
			UpdatedAt
		FROM TruckerOrders
		WHERE AssignedPlayerID = ?
		  AND Status IN ('accepted', 'pickup', 'in_transit')
		ORDER BY UpdatedAt DESC
		LIMIT 1
	]], { pid })

	local r = RowsFirst(rows)
	if not r then return nil end

	return {
		id = tostring(DB.RowGet(r, "ID") or ""),
		assignedPlayerId = DB.RowGet(r, "AssignedPlayerID"),
		title = tostring(DB.RowGet(r, "Title") or ""),
		clientName = tostring(DB.RowGet(r, "ClientName") or ""),
		cargoName = tostring(DB.RowGet(r, "CargoName") or ""),
		cargoClass = tostring(DB.RowGet(r, "CargoClass") or "standard"),
		weightKg = tonumber(DB.RowGet(r, "WeightKg") or 0) or 0,
		pickupLabel = tostring(DB.RowGet(r, "PickupLabel") or ""),
		dropoffLabel = tostring(DB.RowGet(r, "DropoffLabel") or ""),
		distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
		reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
		deposit = tonumber(DB.RowGet(r, "Deposit") or 0) or 0,
		vehicleClass = DB.RowGet(r, "VehicleClass"),
		trailerRequired = (tonumber(DB.RowGet(r, "TrailerRequired") or 0) == 1),
		status = tostring(DB.RowGet(r, "Status") or "accepted"),
		estimatedMinutes = tonumber(DB.RowGet(r, "EstimatedMinutes") or 0) or 0,
		deadlineAt = tonumber(DB.RowGet(r, "DeadlineAt") or 0) or 0,
		description = DB.RowGet(r, "Description"),
		minLevel = tonumber(DB.RowGet(r, "MinLevel") or 1) or 1,
		requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
		iconImage = DB.RowGet(r, "IconImage"),
		truckImage = DB.RowGet(r, "TruckImage"),
		trailerImage = DB.RowGet(r, "TrailerImage"),
		cargoImage = DB.RowGet(r, "CargoImage"),
		createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
		updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
	}
end

function DB.Trucker.TryAssignOrder(orderId, playerId)
	EnsureReady()

	local oid = tostring(orderId or "")
	local pid = tostring(playerId or "")
	if oid == "" or pid == "" then return false end

	local now = Now()

	return Database.Execute([[
		UPDATE TruckerOrders
		SET
			AssignedPlayerID = ?,
			Status = 'accepted',
			UpdatedAt = ?
		WHERE ID = ?
		  AND Status = 'available'
		  AND (AssignedPlayerID IS NULL OR AssignedPlayerID = '')
	]], {
		pid, now, oid
	}) == true
end

-- =========================
-- Courier
-- =========================

DB.Courier = DB.Courier or {}

function DB.Courier.GetProfile(playerId)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return nil end

	local rows = Database.Select([[
		SELECT
			PlayerID,
			Level,
			Rating,
			CompletedJobs,
			TotalEarned,
			SkillPoints,
			UpdatedAt
		FROM CourierProfiles
		WHERE PlayerID = ?
		LIMIT 1
	]], { pid })

	local r = RowsFirst(rows)
	if not r then return nil end

	return {
		playerId = tostring(DB.RowGet(r, "PlayerID") or pid),
		level = tonumber(DB.RowGet(r, "Level") or 1) or 1,
		rating = tonumber(DB.RowGet(r, "Rating") or 5.0) or 5.0,
		completedJobs = tonumber(DB.RowGet(r, "CompletedJobs") or 0) or 0,
		totalEarned = tonumber(DB.RowGet(r, "TotalEarned") or 0) or 0,
		skillPoints = tonumber(DB.RowGet(r, "SkillPoints") or 0) or 0,
		updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
	}
end

function DB.Courier.EnsureProfile(playerId)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return nil end

	local existing = DB.Courier.GetProfile(pid)
	if existing then return existing end

	local now = Now()

	Database.Execute([[
		INSERT INTO CourierProfiles (
			PlayerID, Level, Rating, CompletedJobs, TotalEarned, SkillPoints, UpdatedAt
		) VALUES (?, ?, ?, ?, ?, ?, ?)
	]], {
		pid, 1, 5.0, 0, 0, 0, now
	})

	return DB.Courier.GetProfile(pid)
end

function DB.Courier.GetJobById(jobId)
	EnsureReady()

	local id = tostring(jobId or "")
	if id == "" then return nil end

	local rows = Database.Select([[
		SELECT
			ID, PlayerID, Title, Customer, Pickup, Dropoff,
			Reward, DistanceKm, Status, Priority,
			RequiredSkillsJson, Notes, InvoiceNumber,
			CreatedAt, UpdatedAt, CompletedAt
		FROM CourierJobs
		WHERE ID = ?
		LIMIT 1
	]], { id })

	local r = RowsFirst(rows)
	if not r then return nil end

	return {
		id = tostring(DB.RowGet(r, "ID") or ""),
		playerId = DB.RowGet(r, "PlayerID"),
		title = tostring(DB.RowGet(r, "Title") or ""),
		customer = tostring(DB.RowGet(r, "Customer") or ""),
		pickup = tostring(DB.RowGet(r, "Pickup") or ""),
		dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
		reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
		distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
		status = tostring(DB.RowGet(r, "Status") or "available"),
		priority = tostring(DB.RowGet(r, "Priority") or "normal"),
		requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
		notes = tostring(DB.RowGet(r, "Notes") or ""),
		invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
		createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
		updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
	}
end

function DB.Courier.ListAvailableJobs(limit)
	EnsureReady()

	local lim = tonumber(limit) or 50

	local rows = Database.Select([[
		SELECT
			ID, PlayerID, Title, Customer, Pickup, Dropoff,
			Reward, DistanceKm, Status, Priority,
			RequiredSkillsJson, Notes, InvoiceNumber,
			CreatedAt, UpdatedAt, CompletedAt
		FROM CourierJobs
		WHERE Status IN ('available', 'active')
		ORDER BY CreatedAt DESC
		LIMIT ?
	]], { lim })

	local out = {}
	local n = RowsCount(rows)

	for i = 1, n do
		local r = RowAt(rows, i)
		out[#out + 1] = {
			id = tostring(DB.RowGet(r, "ID") or ""),
			playerId = DB.RowGet(r, "PlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			customer = tostring(DB.RowGet(r, "Customer") or ""),
			pickup = tostring(DB.RowGet(r, "Pickup") or ""),
			dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			status = tostring(DB.RowGet(r, "Status") or "available"),
			priority = tostring(DB.RowGet(r, "Priority") or "normal"),
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			notes = tostring(DB.RowGet(r, "Notes") or ""),
			invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
			completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
		}
	end

	return out
end

function DB.Courier.GetActiveJob(playerId)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return nil end

	local rows = Database.Select([[
		SELECT
			ID, PlayerID, Title, Customer, Pickup, Dropoff,
			Reward, DistanceKm, Status, Priority,
			RequiredSkillsJson, Notes, InvoiceNumber,
			CreatedAt, UpdatedAt, CompletedAt
		FROM CourierJobs
		WHERE PlayerID = ? AND Status = 'active'
		ORDER BY UpdatedAt DESC
		LIMIT 1
	]], { pid })

	local r = RowsFirst(rows)
	if not r then return nil end

	return {
		id = tostring(DB.RowGet(r, "ID") or ""),
		playerId = DB.RowGet(r, "PlayerID"),
		title = tostring(DB.RowGet(r, "Title") or ""),
		customer = tostring(DB.RowGet(r, "Customer") or ""),
		pickup = tostring(DB.RowGet(r, "Pickup") or ""),
		dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
		reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
		distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
		status = tostring(DB.RowGet(r, "Status") or "active"),
		priority = tostring(DB.RowGet(r, "Priority") or "normal"),
		requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
		notes = tostring(DB.RowGet(r, "Notes") or ""),
		invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
		createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
		updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
	}
end

function DB.Courier.ListHistory(playerId, limit)
	EnsureReady()

	local pid = tostring(playerId or "")
	local lim = tonumber(limit) or 50
	if pid == "" then return {} end

	local rows = Database.Select([[
		SELECT
			ID, PlayerID, Title, Customer, Pickup, Dropoff,
			Reward, DistanceKm, Status, Priority,
			RequiredSkillsJson, Notes, InvoiceNumber,
			CreatedAt, UpdatedAt, CompletedAt
		FROM CourierJobs
		WHERE PlayerID = ? AND Status IN ('completed', 'cancelled')
		ORDER BY UpdatedAt DESC
		LIMIT ?
	]], { pid, lim })

	local out = {}
	local n = RowsCount(rows)

	for i = 1, n do
		local r = RowAt(rows, i)
		out[#out + 1] = {
			id = tostring(DB.RowGet(r, "ID") or ""),
			title = tostring(DB.RowGet(r, "Title") or ""),
			customer = tostring(DB.RowGet(r, "Customer") or ""),
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			status = tostring(DB.RowGet(r, "Status") or ""),
			invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
			completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
		}
	end

	return out
end

function DB.Courier.UpsertInvoice(data)
	EnsureReady()

	data = type(data) == "table" and data or {}

	local invoiceId = tostring(data.invoiceId or "")
	local playerId = tostring(data.playerId or "")
	local jobId = tostring(data.jobId or "")
	local status = tostring(data.status or "printed")
	local metaJson = data.metaJson ~= nil and tostring(data.metaJson) or nil

	if invoiceId == "" or playerId == "" or jobId == "" then
		return false
	end

	local now = Now()

	local existing = Database.Select([[
		SELECT InvoiceID
		FROM CourierInvoices
		WHERE InvoiceID = ?
		LIMIT 1
	]], { invoiceId })

	if RowsCount(existing) <= 0 then
		return Database.Execute([[
			INSERT INTO CourierInvoices (
				InvoiceID, PlayerID, JobID, Status, MetaJson, CreatedAt, UpdatedAt
			) VALUES (?, ?, ?, ?, ?, ?, ?)
		]], {
			invoiceId, playerId, jobId, status, metaJson, now, now
		}) == true
	end

	return Database.Execute([[
		UPDATE CourierInvoices SET
			PlayerID = ?,
			JobID = ?,
			Status = ?,
			MetaJson = ?,
			UpdatedAt = ?
		WHERE InvoiceID = ?
	]], {
		playerId, jobId, status, metaJson, now, invoiceId
	}) == true
end

function DB.Courier.ListOpenJobs(limit)
	EnsureReady()

	local lim = tonumber(limit) or 50

	local rows = Database.Select([[
		SELECT
			ID, PlayerID, Title, Customer, Pickup, Dropoff,
			Reward, DistanceKm, Status, Priority,
			RequiredSkillsJson, Notes, InvoiceNumber,
			CreatedAt, UpdatedAt, CompletedAt
		FROM CourierJobs
		WHERE (PlayerID IS NULL OR PlayerID = '')
		  AND Status = 'available'
		ORDER BY CreatedAt DESC
		LIMIT ?
	]], { lim })

	local out = {}
	local n = RowsCount(rows)

	for i = 1, n do
		local r = RowAt(rows, i)
		out[#out + 1] = {
			id = tostring(DB.RowGet(r, "ID") or ""),
			playerId = DB.RowGet(r, "PlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			customer = tostring(DB.RowGet(r, "Customer") or ""),
			pickup = tostring(DB.RowGet(r, "Pickup") or ""),
			dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			status = tostring(DB.RowGet(r, "Status") or "available"),
			priority = tostring(DB.RowGet(r, "Priority") or "normal"),
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			notes = tostring(DB.RowGet(r, "Notes") or ""),
			invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
			completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
		}
	end

	return out
end

function DB.Courier.GetAnyOwnedActiveJob(playerId)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return nil end

	local rows = Database.Select([[
		SELECT
			ID, PlayerID, Title, Customer, Pickup, Dropoff,
			Reward, DistanceKm, Status, Priority,
			RequiredSkillsJson, Notes, InvoiceNumber,
			CreatedAt, UpdatedAt, CompletedAt
		FROM CourierJobs
		WHERE PlayerID = ?
		  AND Status IN ('active', 'pickup', 'delivery', 'accepted')
		ORDER BY UpdatedAt DESC
		LIMIT 1
	]], { pid })

	local r = RowsFirst(rows)
	if not r then return nil end

	return {
		id = tostring(DB.RowGet(r, "ID") or ""),
		playerId = DB.RowGet(r, "PlayerID"),
		title = tostring(DB.RowGet(r, "Title") or ""),
		customer = tostring(DB.RowGet(r, "Customer") or ""),
		pickup = tostring(DB.RowGet(r, "Pickup") or ""),
		dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
		reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
		distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
		status = tostring(DB.RowGet(r, "Status") or "active"),
		priority = tostring(DB.RowGet(r, "Priority") or "normal"),
		requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
		notes = tostring(DB.RowGet(r, "Notes") or ""),
		invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
		createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
		updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
	}
end

function DB.Courier.TryAssignJob(jobId, playerId)
	EnsureReady()

	local jid = tostring(jobId or "")
	local pid = tostring(playerId or "")
	if jid == "" or pid == "" then return false end

	local now = Now()

	return Database.Execute([[
		UPDATE CourierJobs
		SET
			PlayerID = ?,
			Status = 'active',
			UpdatedAt = ?
		WHERE ID = ?
		  AND (PlayerID IS NULL OR PlayerID = '')
		  AND Status = 'available'
	]], {
		pid, now, jid
	}) == true
end

function DB.Courier.MarkJobCompleted(jobId, playerId)
	EnsureReady()

	local jid = tostring(jobId or "")
	local pid = tostring(playerId or "")
	if jid == "" or pid == "" then return false end

	local now = Now()

	return Database.Execute([[
		UPDATE CourierJobs
		SET
			Status = 'completed',
			UpdatedAt = ?,
			CompletedAt = ?
		WHERE ID = ?
		  AND PlayerID = ?
		  AND Status IN ('active', 'pickup', 'delivery', 'accepted')
	]], {
		now, now, jid, pid
	}) == true
end

function DB.Courier.CancelJob(jobId, playerId)
	EnsureReady()

	local jid = tostring(jobId or "")
	local pid = tostring(playerId or "")
	if jid == "" or pid == "" then return false end

	local now = Now()

	return Database.Execute([[
		UPDATE CourierJobs
		SET
			Status = 'cancelled',
			UpdatedAt = ?
		WHERE ID = ?
		  AND PlayerID = ?
		  AND Status IN ('active', 'pickup', 'delivery', 'accepted')
	]], {
		now, jid, pid
	}) == true
end

function DB.Courier.GetSkills(playerId)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then
		return {
			standard = 0,
			fragile = 0,
			medical = 0,
			secure = 0,
		}
	end

	return {
		standard = 0,
		fragile = 0,
		medical = 0,
		secure = 0,
	}
end

function DB.Courier.UpdateProfileProgress(playerId, reward)
	EnsureReady()

	local pid = tostring(playerId or "")
	if pid == "" then return false end

	local amount = tonumber(reward or 0) or 0
	local profile = DB.Courier.EnsureProfile(pid)
	if not profile then return false end

	local now = Now()
	local nextCompletedJobs = (tonumber(profile.completedJobs or 0) or 0) + 1
	local nextTotalEarned = (tonumber(profile.totalEarned or 0) or 0) + amount

	local currentLevel = tonumber(profile.level or 1) or 1
	local nextLevel = currentLevel

	if nextCompletedJobs >= (currentLevel * 5) then
		nextLevel = currentLevel + 1
	end

	return Database.Execute([[
		UPDATE CourierProfiles
		SET
			Level = ?,
			CompletedJobs = ?,
			TotalEarned = ?,
			UpdatedAt = ?
		WHERE PlayerID = ?
	]], {
		nextLevel,
		nextCompletedJobs,
		nextTotalEarned,
		now,
		pid
	}) == true
end

--]=]

-- =========================
-- Domain modules
-- =========================

local function ApplyDomainModule(moduleName)
	local ok, mod = pcall(require, moduleName)
	if ok and type(mod) == "function" then
		mod(DB)
		return true
	end
	return false
end

ApplyDomainModule("db.chat")
ApplyDomainModule("db.communications")
if LegacyLocalDomainSchemaEnabled() then
	ApplyDomainModule("db.jobs")
end
ApplyDomainModule("db.photos")
if not ApplyDomainModule("db.parking") then
	error("DB.Init: Failed to load parking persistence module")
end
if not ApplyDomainModule("db.documents") then
	error("DB.Init: Failed to load document persistence module")
end

function DB.Shutdown()
	if Database and Database.Close then
		Log("closing database")
		pcall(function()
			Database.Close()
		end)
	end

	isReady = false
end

return DB
