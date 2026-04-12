-- ScaleHandler.lua
-- Универсальный обработчик масштабирования UI без артефактов и скачков.
-- Для репозитория ShardAI/sharduigayedition (ветка russian-expletive-cleanup-36a53)
-- Автор: Senior Lua Dev

local C_Timer = C_Timer
local type = type
local math_huge = math.huge
local error = error
local unpack = unpack or table.unpack

-- Константы валидации диапазона масштаба
local MIN_SCALE = 0.1
local MAX_SCALE = 10.0

--[[
    Создаёт замыкание для безопасного масштабирования объекта.
    
    @param baseObject Frame - Объект UI для масштабирования.
                       Должен быть валидным фреймом с методами GetPoint/SetPoint/SetScale.
    
    @return function(scaleCoefficient) - Колбэк для установки масштаба.
             Принимает число от 0.1 до 10.0, автоматически применяет clamp.
    
    Особенности реализации:
    - Используем SetScale() вместо ручного изменения Width/Height — это правильно.
    - Сохраняем AnchorPoint через переприменение точки привязки после зума.
    - Дочерние элементы масштабируются автоматически через иерархию Roblox.
    - Троттлинг на 16мс защищает от спама при драге слайдера.
    - Применяем масштаб только когда фрейм видим — избегаем артефактов рендеринга.
]]
local function CreateScaleHandler(baseObject)
    -- Валидация входного объекта на этапе создания (fail-fast принцип).
    -- Если передали мусор — ошибка возникнет сразу, а не при первом вызове.
    if not baseObject or type(baseObject) ~= "table" then
        error("CreateScaleHandler: baseObject must be a valid UI Frame, got " .. type(baseObject), 2)
    end

    -- Кэшируем начальную точку привязки ОДИН раз при создании.
    -- Это критично: после SetScale() координаты могут сбиться, если якорь сложный.
    -- Переприменение той же точки заставляет движок пересчитать AbsolutePosition корректно.
    local initialAnchor = {baseObject:GetPoint(0)}
    
    -- Переменные для троттлинга (debounce) — защита от rapid-fire вызовов.
    local pendingScale = nil
    local isThrottled = false

    -- Внутренняя функция применения масштаба.
    -- Выносится отдельно для переиспользования в основном потоке и в C_Timer.
    local function ApplyScale(value)
        -- Финальная валидация перед применением (NaN может проскочить).
        if value ~= value then -- Проверка на NaN: NaN ~= NaN всегда true.
            error("ScaleHandler: Attempted to set NaN scale", 2)
        end
        
        -- Clamp значений в допустимый диапазон [0.1, 10.0].
        -- Защита от дурака: даже если передали 0 или 100 — будет обрезано.
        if value < MIN_SCALE then 
            value = MIN_SCALE 
        end
        if value > MAX_SCALE then 
            value = MAX_SCALE 
        end

        -- Применяем масштаб ТОЛЬКО если объект видим.
        -- Это предотвращает артефакты рендеринга при скрытых элементах.
        -- Невидимый фрейм с изменённым Scale может «мигнуть» при появлении.
        if baseObject:IsVisible() then
            baseObject:SetScale(value)
            
            -- Жесткая фиксация якоря после изменения масштаба.
            -- Движок Roblox иногда сбивает оффсеты при зуме, если точка привязки сложная.
            -- Переприменяем ту же точку, чтобы координаты пересчитались корректно.
            -- unpack нужен, чтобы развернуть таблицу {Point, X, Y, ScaleX, ScaleY} в аргументы.
            baseObject:SetPoint(unpack(initialAnchor))
        end

        -- Сбрасываем флаги троттлинга после успешного применения.
        pendingScale = nil
        isThrottled = false
    end

    -- Возвращаем публичный колбэк — функцию, принимающую один аргумент.
    -- Эта функция будет вызываться из OnValueChanged слайдера или OnTextChanged editbox.
    return function(scaleCoefficient)
        -- 1. Строгая проверка типа.
        -- type(nan) == "number" в Lua, поэтому NaN проверяем отдельно ниже.
        if type(scaleCoefficient) ~= "number" then
            error("ScaleHandler: Scale must be number, got " .. type(scaleCoefficient), 2)
        end

        -- 2. Обработка NaN явно.
        -- Это единственный случай, когда number недопустим.
        if scaleCoefficient ~= scaleCoefficient then
            error("ScaleHandler: Scale cannot be NaN", 2)
        end

        -- 3. Логика троттлинга (защита от спама при драге слайдера).
        -- Если уже идёт обработка в текущем кадре, просто обновляем «желаемое» значение.
        -- Старое значение будет перезаписано — нам важно только последнее.
        if isThrottled then
            pendingScale = scaleCoefficient
            return
        end

        -- Мгновенное применение первого вызова.
        -- Это даёт отзывчивость: пользователь видит результат сразу.
        isThrottled = true
        ApplyScale(scaleCoefficient)

        -- Планируем проверку очереди на следующий кадр (~16мс = 60 FPS).
        -- Используем 0.016 для гарантии попадания в следующий рендер-тик.
        -- Если за это время были ещё вызовы — применим последнее значение.
        C_Timer.After(0.016, function()
            if pendingScale then
                ApplyScale(pendingScale)
            end
        end)
    end
end

return CreateScaleHandler
