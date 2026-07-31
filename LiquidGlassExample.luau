-- Демонстрация эффекта LiquidGlass
local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/ShardAI/sharduigayedition/main/Library.luau'))()

-- ВКЛЮЧИТЬ эффект жидкого стекла ДО создания окна
Library.LiquidGlass = true

local Window = Library:CreateWindow({
    Title = 'Liquid Glass Demo',
    Center = true,
    AutoShow = true,
})

-- Создать standalone стеклянный элемент
local GlassPanel = Library:CreateLiquidGlass({
    Size = UDim2.fromOffset(300, 200),
    Position = UDim2.new(0.5, -150, 0.5, -100),
    AnchorPoint = Vector2.new(0.5, 0.5),
    TintTransparency = 0.25,
    Reflectivity = 0.7,
    Parent = Library.ScreenGui,
})

-- Дочерний элемент внутри стекла
local Label = Instance.new('TextLabel')
Label.Size = UDim2.new(1, 0, 0, 30)
Label.BackgroundTransparency = 1
Label.Text = 'Panel behind me'
Label.TextColor3 = Color3.new(1, 1, 1)
Label.Font = Enum.Font.Code
Label.TextSize = 14
Label.Parent = GlassPanel:GetContentFrame()

-- Наслоение: внутренний элемент внутри внешнего
local InnerGlass = Library:CreateLiquidGlass({
    Size = UDim2.new(0.8, 0, 0.6, 0),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    TintTransparency = 0.4,
    Reflectivity = 0.85, -- сильнее блик
    Parent = GlassPanel, -- автоматически станет вложенным
})

-- Анимация при необходимости
task.wait(2)
GlassPanel:PlayMorph(0.4)

-- Классический Roblox API работает через нижележащий Frame
GlassPanel:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
    print('Size changed to', GlassPanel.Root.AbsoluteSize)
end)

-- Очистка
task.delay(10, function()
    GlassPanel:Destroy()
end)
