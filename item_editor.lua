-- ========== 用户自定义配置 ==========
--
local FONT_SCALE = 1.2
local FONT_NAME = "SourceHanSansCN-Regular.otf"

-- ========== 常量和结构定义 ==========
--
---@class ItemSource
local ItemSource = {
    Pouch = 1,
    Box = 2
}

---@class ItemDefinition
---@field fixed_id integer
---@field name string

---@class Task
---@field cb fun (...)
---@field args any[]

local REPOSITORY = "https://github.com/eigeen/ref-mhws-item-editor"
local VERSION = "1.0.3"
local AUTHOR = "eigeen"
local DESCRIPTION =
    -- "当前为实验性版本，可能遇到任何bug，报错请重载插件（不是重启游戏）。在上面的仓库里获取最新版。"
    "Experimental version, may encounter bugs, please reload the plugin (not restart the game)."

-- ========== 全局变量 ==========

local g_editor_open = false
local g_item_source = ItemSource.Pouch
local g_rem = imgui.get_default_font_size() * FONT_SCALE
local g_font = imgui.load_font(FONT_NAME, g_rem, {0x0020, 0xE007F, 0})

-- ========== 游戏内结构缓存初始化 ==========

local LazyStaticState = {
    Uninitialized = 0,
    Initialized = 1
}

---@class LazyStatic
local LazyStatic = {}
LazyStatic.__index = LazyStatic

function LazyStatic.new(init_fn)
    local obj = setmetatable({}, LazyStatic)
    obj.init_fn = init_fn
    obj.state = LazyStaticState.Uninitialized
    obj.inner_value = nil
    return obj
end

function LazyStatic:value()
    if self.state == LazyStaticState.Uninitialized then
        local init_fn = self.init_fn
        self.inner_value = init_fn()
        self.state = LazyStaticState.Initialized
    end

    return self.inner_value
end

---@type LazyStatic<app.SaveDataManager>
local lz_app_SaveDataManager = LazyStatic.new(function()
    return sdk.get_managed_singleton("app.SaveDataManager")
end)
---@type LazyStatic<app.VariousDataManager>
local lz_various_data_manager_setting = LazyStatic.new(function()
    return sdk.get_managed_singleton("app.VariousDataManager")
end)
---@type via.gui.message
local via_gui_message = sdk.find_type_definition("via.gui.message")
local get_name_fn = via_gui_message:get_method("get(System.Guid)")
---@type app.ItemDef
local app_ItemDef = sdk.find_type_definition("app.ItemDef")
local item_id_fn = app_ItemDef:get_method("ItemId(app.ItemDef.ID)")

-- ========== 工具方法 ==========

--- 获取名称
---@param guid System.Guid
---@return string
local function get_name(guid)
    local result = get_name_fn:call(nil, guid)
    if not result then
        return ""
    end

    return tostring(result)
end

---@class ItemHelper
local ItemHelper = {
    item_definitions = nil,
    item_works = {},
    combo_items_all = nil
}
ItemHelper.__index = ItemHelper

function ItemHelper:update()
    self:update_item_works()
end

-- 更新当前道具列表
function ItemHelper:update_item_works()
    local app_savedata_cItemParam = self:get_citem_param()

    self.item_works[ItemSource.Pouch] = app_savedata_cItemParam:get_PouchItem()
    self.item_works[ItemSource.Box] = app_savedata_cItemParam:get_BoxItem()
end

--- 初始化物品定义
--- 在使用时第一次调用，防止过早初始化丢失一些对象和语言设置
function ItemHelper:init_item_definitions()
    local item_setting = lz_various_data_manager_setting:value():get_Setting():get_Item()

    local item_data = item_setting:get_ItemData()

    local item_values = item_data:getValues()
    local item_len = item_data:getDataNum()

    self.item_definitions = {}

    for i = 0, item_len - 1 do
        ---@type app.user_data.ItemData.cData
        local item_value = item_values[i]
        local name_id = item_value:get_RawName()

        local name = get_name(name_id)
        ---@type app.ItemDef.ID_Fixed
        local fixed_id = item_value:get_ItemId()

        self.item_definitions[fixed_id] = {
            fixed_id = fixed_id,
            name = name
        }
    end
end

---@return app.savedata.cItemParam
function ItemHelper:get_citem_param()
    local app_savedata_cUserSaveParam = lz_app_SaveDataManager:value():getCurrentUserSaveData()
    local app_savedata_cItemParam = app_savedata_cUserSaveParam:get_Item()

    return app_savedata_cItemParam
end

---@return app.savedata.cBasicParam
function ItemHelper:get_cbasic_param()
    local app_savedata_cUserSaveParam = lz_app_SaveDataManager:value():getCurrentUserSaveData()
    local app_savedata_cBasicParam = app_savedata_cUserSaveParam:get_BasicData()

    return app_savedata_cBasicParam
end

---@return table<app.ItemDef.ID_Fixed, ItemDefinition>
function ItemHelper:get_item_definitions()
    if not self.item_definitions then
        self:init_item_definitions()
    end

    return self.item_definitions
end

--- 获取当前道具列表
---@param item_source ItemSource
---@return table<integer, app.savedata.cItemWork>
function ItemHelper:get_current_items(item_source)
    local item_works = self.item_works[item_source]
    if not item_works then
        return {}
    end

    return item_works
end

--- 通过FixedID查找物品定义
---@param fixed_id app.ItemDef.ID_Fixed
---@return ItemDefinition | nil
function ItemHelper:get_item_definition_by_id(fixed_id)
    local item_definitions = self:get_item_definitions()

    if item_definitions[fixed_id] then
        return item_definitions[fixed_id]
    end

    return nil
end

--- 物品ID转换为固定ID
---@param id app.ItemDef.ID
---@return app.ItemDef.ID_Fixed
function ItemHelper:id_to_fixed_id(id)
    return item_id_fn:call(nil, id)
end

function ItemHelper:create_combo_item_name(fixed_id, name)
    return tostring(fixed_id) .. " " .. name
end

-- 获取Combo容器的内容列表
function ItemHelper:get_combo_items_all()
    if self.combo_items_all then
        return self.combo_items_all
    end

    local combo_items = {}

    for _, item_def in pairs(self:get_item_definitions()) do
        combo_items[item_def.fixed_id] = self:create_combo_item_name(item_def.fixed_id, item_def.name)
    end

    -- -- 按FIXED_ID排序
    -- local sorted_ids = {}
    -- for id in pairs(combo_items) do
    --     table.insert(sorted_ids, id)
    -- end
    -- table.sort(sorted_ids)

    -- local sorted_combo_items = {}
    -- for _, id in ipairs(sorted_ids) do
    --     sorted_combo_items[id] = combo_items[id]
    -- end

    self.combo_items_all = combo_items

    return combo_items
end

---@class TaskTable @发送到主线程执行的任务
local TaskTable = {}
TaskTable.__index = TaskTable

function TaskTable:push(task_fn, ...)
    table.insert(self, {
        cb = task_fn,
        args = {...}
    })
end

---@return Task
function TaskTable:pop()
    return table.remove(self, 1)
end

function TaskTable:is_empty()
    return #self == 0
end

---@return integer
function TaskTable:size()
    return #self
end

---@param cbasic_param app.savedata.cBasicParam
---@param delta integer
local function task_add_money(cbasic_param, delta)
    cbasic_param:addMoney(delta, true)
end

---@param cbasic_param app.savedata.cBasicParam
---@param delta integer
local function task_add_point(cbasic_param, delta)
    cbasic_param:addPoint(delta, true)
end

-- ========== 绘制方法 ==========

--- 关闭物品编辑器窗口
local function close_item_editor()
    g_editor_open = false
end

---@return app.ItemDef.ID_Fixed | integer | nil
local function get_id_from_combo_item(combo_item)
    local id_str = string.match(combo_item, "^%d+")
    if not id_str then
        return nil
    end

    return tonumber(id_str)
end

--- 绘制物品列表
local function draw_item_list()
    -- 获取当前物品
    local items = ItemHelper:get_current_items(g_item_source)

    -- 绘制物品列表
    imgui.begin_table("##item_list", 2, 0, nil, 0.0)
    imgui.table_setup_column("Item")
    imgui.table_setup_column("Count")
    imgui.table_headers_row()

    for key, itemWork in pairs(items) do
        local item_def = ItemHelper:get_item_definition_by_id(ItemHelper:id_to_fixed_id(itemWork:get_ItemId()))
        if not item_def then
            -- 忽略无定义的物品
            return
        end

        local item_name_with_id = ItemHelper:create_combo_item_name(item_def.fixed_id, item_def.name)

        imgui.table_next_row()

        imgui.table_set_column_index(0)
        local changed, new_item_name_with_id = imgui.combo("##combo__" .. key, item_def.fixed_id,
            ItemHelper:get_combo_items_all())
        if changed then
            local fixed_id = get_id_from_combo_item(new_item_name_with_id)
            if fixed_id then
                itemWork.ItemIdFixed = fixed_id
            end
        end

        imgui.table_set_column_index(1)
        imgui.push_item_width(6 * g_rem)
        local changed, value = imgui.drag_int("##drag_int__" .. key, itemWork.Num, 1, 0, 1000, "%d")
        if changed then
            itemWork.Num = value
        end
    end
    imgui.end_table()
end

--- 绘制物品编辑器窗口
local function draw_item_editor()
    local do_open = imgui.begin_window("Item Editor", true, 0)
    if not do_open then
        close_item_editor()
        imgui.end_window()
        return
    end

    imgui.text("Version: " .. VERSION)
    imgui.text("Author: " .. AUTHOR)
    imgui.text("Repository: " .. REPOSITORY)
    imgui.text("Description: " .. DESCRIPTION)

    -- 当前道具栏模块
    if imgui.tree_node("Edit Items") then
        -- 物品来源选择 道具袋/道具箱等
        -- 模拟实现radio button
        imgui.text("Container")
        local changed, value = imgui.checkbox("Pouch", g_item_source == ItemSource.Pouch)
        if changed and value then
            g_item_source = ItemSource.Pouch
        end
        imgui.same_line()
        local changed, value = imgui.checkbox("Box", g_item_source == ItemSource.Box)
        if changed and value then
            g_item_source = ItemSource.Box
        end

        draw_item_list()

        imgui.tree_pop()
    end

    -- 猎人数据修改模块
    if imgui.tree_node("Edit Hunter Data") then
        local cbasic_param = ItemHelper:get_cbasic_param()
        local money = cbasic_param:getMoney()
        local point = cbasic_param:getPoint()
        local total_point = cbasic_param:getTotalPoint()

        imgui.text("Money")
        imgui.same_line()
        imgui.push_item_width(12 * g_rem)
        local changed, new_value = imgui.drag_int("##drag_int__money", money, 100, 0, 99999999, "%d")
        if changed then
            local delta = new_value - money
            TaskTable:push(task_add_money, cbasic_param, delta)
        end

        imgui.text("Point")
        imgui.same_line()
        imgui.push_item_width(12 * g_rem)
        local changed, new_value = imgui.drag_int("##drag_int__point", point, 100, 0, 99999999, "%d")
        if changed then
            local delta = new_value - point
            TaskTable:push(task_add_point, cbasic_param, delta)
        end

        imgui.tree_pop()
    end

    imgui.end_window()
end

-- UI绘制
re.on_draw_ui(function()
    imgui.push_font(g_font)

    if imgui.tree_node("Item Editor") then
        local open_editor_button_text
        if g_editor_open then
            open_editor_button_text = "Close Editor"
        else
            open_editor_button_text = "Open Editor"
        end
        if imgui.button(open_editor_button_text) then
            g_editor_open = not g_editor_open
        end

        imgui.tree_pop()
    end

    -- draw item editor window
    if g_editor_open then
        ItemHelper:update()

        draw_item_editor()
    end

    imgui.pop_font(g_font)
end)

-- 在主线程处理部分数据操作事件，否则会引起崩溃
sdk.hook(sdk.find_type_definition("app.GUIManager"):get_method("updateApp"), function(args)
    local task = TaskTable:pop()
    if task then
        local cb = task['cb']
        local args = task['args']

        cb(table.unpack(args))
    end
end, function(retval)
end)
