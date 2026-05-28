-- Betterflags
-- Better flag implementation! Adds Meatball Flag, No-overtake zones, and Slow Car Ahead flag from ACC. Can display them all in parallel.
--
-- If you open the "Chat" app, and click the lightbulb, you can preview and move the flags anywhere on screen.
--
-- Put the following into your AC server CSP EXTRA OPTIONS:
--
-- [SCRIPT_...]
-- SCRIPT = "https://raw.githubusercontent.com/JanuarySnow/OSRLUASNIPPETS/refs/heads/main/Server%20Scripts/betterflags.lua"
--
-- [BETTERFLAGS]
-- NO_OVERTAKE_ZONE_1=0.2,0.3 ;Defines the First no-overtake zone as two points on track, flag will be displayed between them.
-- NO_OVERTAKE_ZONE_2=0,0 ;Use the track coordinates app from the ingame App Shelf app to quickly find the track coordinates.
-- NO_OVERTAKE_ZONE_3=0,0
-- MEATBALL_THRESHOLD=0.10 ;Suspension Damage Threshold to display meatball flag. Value from 0-1. Lower = more sensitive.
-- SLOW_CAR_WARN_DISTANCE=500,100 ;how far in front and behind to enable slow car. (500,100 means slow car flag would be active 500m before and 100m after slow car)
-- SLOW_CAR_PENALTY=-1,5 ; -1 for no penalty (white flag) , 0 for chat message (code60 flag), anything above will be laps to serve drive through (code60 flag).
-- ;optional second value is how long people have to slow down to 60kmh.
-- SLOW_CAR_CONFIRM_DELAY=3.0 ;how many seconds a car must be stationary before the slow car flag appears. Default is 3.0.
-- ENABLE_PHYSICS_FLAGS=1 ;experimental, activates ac yellow under slow car conditions.
--
-- if youre still stuck check here: https://github.com/ac-custom-shaders-patch/acc-extension-config/wiki/Misc-%E2%80%93-Server-extra-options#online-scripts


function initialization()
SIM = ac.getSim()
CAR = ac.getCar(SIM.focusedCar)

isWarning = false
timeWarningStarted = 0

settingsOverride = false
windowWidth, windowHeight = ac.getSim().windowWidth,ac.getSim().windowHeight
uiScale = ac.getUI().uiScale
testGameState = false
code60Timing = 0
code60Grace = 0

slowCarTimers = {}
frameCounter = 0
SLOW_CAR_CHECK_INTERVAL = 60
SLOW_CAR_CONFIRM_DELAY = 3.0
slowCarConfirmed = false
slowCarPenaltySet = false
raceStarted = false

betterFlagSettings = ac.storage({
    flagWindowX=0,flagWindowY=0,flagWindowScale=1
})

tempSettings = betterFlagSettings

ac.blockSystemMessages("$CSP0:")

end
ac.onOnlineWelcome(function(message, config)
    parsedConfig = tostring(config)
    configCheck = config:mapSection("BETTERFLAGS", { NO_OVERTAKE_ZONE_1 = {0,0}, NO_OVERTAKE_ZONE_2 = {0,0}, NO_OVERTAKE_ZONE_3 = {0,0}})

    noOvertake1_S,noOvertake1_E = config:get("BETTERFLAGS", "NO_OVERTAKE_ZONE_1", 0), config:get("BETTERFLAGS", "NO_OVERTAKE_ZONE_1", 0,2)
    noOvertake2_S,noOvertake2_E = config:get("BETTERFLAGS", "NO_OVERTAKE_ZONE_2", 0), config:get("BETTERFLAGS", "NO_OVERTAKE_ZONE_2", 0,2)
    noOvertake3_S,noOvertake3_E = config:get("BETTERFLAGS", "NO_OVERTAKE_ZONE_3", 0), config:get("BETTERFLAGS", "NO_OVERTAKE_ZONE_3", 0,2)
    meatballThreshold = config:get("BETTERFLAGS", "MEATBALL_THRESHOLD", 0.10)
    slowCarFlagPersist = (config:get("BETTERFLAGS", "SLOW_CAR_FLAG_PERSIST", 1.1))*1000
    slowCarDistanceBehind, slowCarDistanceAhead = (config:get("BETTERFLAGS", "SLOW_CAR_WARN_DISTANCE", 500,1)), (config:get("BETTERFLAGS", "SLOW_CAR_WARN_DISTANCE", 100,2))
    slowCarSpeed = (config:get("BETTERFLAGS", "SLOW_CAR_SPEED", 35))
    slowCarPenalties, code60Timer = (config:get("BETTERFLAGS", "SLOW_CAR_PENALTY", -1,1)),(config:get("BETTERFLAGS", "SLOW_CAR_PENALTY", 5,2))
    SLOW_CAR_CONFIRM_DELAY = config:get("BETTERFLAGS", "SLOW_CAR_CONFIRM_DELAY", 3.0)
    enablePhysicsFlags = config:get("BETTERFLAGS", "ENABLE_PHYSICS_FLAGS", 1)

    ac.log("Slow Car Test Stuff:")
    ac.log(slowCarDistanceBehind, slowCarDistanceAhead)
    ac.log(slowCarPenalties, code60Timer)
end)

    ac.debug("!version", "betterflags v0.67")

function makeFlags()

    startFlag = ui.ExtraCanvas(vec2(256,256))
    startFlag:setName("startFlag")
    startFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.Start)
    end)

    cautionFlag = ui.ExtraCanvas(vec2(256,256))
    cautionFlag:setName("cautionFlag")
    cautionFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.Caution)
    end)

    slipperyFlag = ui.ExtraCanvas(vec2(256,256))
    slipperyFlag:setName("slipperyFlag")
    slipperyFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.Slippery)
    end)

    blackFlag = ui.ExtraCanvas(vec2(256,256))
    blackFlag:setName("blackFlag")
    blackFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.Stop)
    end)

    whiteFlag = ui.ExtraCanvas(vec2(256,256))
    whiteFlag:setName("whiteFlag")
    whiteFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.SlowVehicle)
    end)

    ambulanceFlag = ui.ExtraCanvas(vec2(256,256))
    ambulanceFlag:setName("ambulanceFlag")
    ambulanceFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.Ambulance)
    end)

    blackWhiteFlag = ui.ExtraCanvas(vec2(256,256))
    blackWhiteFlag:setName("blackWhiteFlag")
    blackWhiteFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.ReturnToPits)
    end)

    meatballFlag = ui.ExtraCanvas(vec2(256,256))
    meatballFlag:setName("meatballFlag")
    meatballFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.MechanicalFailure)
    end)

    blueFlag = ui.ExtraCanvas(vec2(256,256))
    blueFlag:setName("blueFlag")
    blueFlag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.FasterCar)
    end)

    code60Flag = ui.ExtraCanvas(vec2(256,256))
    code60Flag:setName("code60Flag")
    code60Flag:update(function (dt)
        ui.drawRaceFlag(ac.FlagType.Code60)
    end)

    flagsWindow = ui.ExtraCanvas(vec2(windowWidth,windowHeight))
    flagsWindow:setName("FlagWindow")

    NoOver = {true,slipperyFlag}
    Slow = {true, whiteFlag}
    Meatball = {true, meatballFlag}
    Code60 = {false , code60Flag}

    currentFlags = {NoOver,Slow,Meatball,Code60}


end

initialization()
makeFlags()

ac.onSessionStart(function() initialization() end)

function script.update(dt)

    totalElapsedTime = SIM.currentSessionTime
    trackProgress = CAR.splinePosition

    frameCounter = frameCounter + 1

    updateSlowCarTimers(dt)

    if frameCounter >= SLOW_CAR_CHECK_INTERVAL then
        frameCounter = 0
        slowCarConfirmed = checkSlowCarPresence()
    end

    flagHandler(dt)
    penalties(dt)
end

function updateSlowCarTimers(dt)
    for carIdx, timer in pairs(slowCarTimers) do
        local car = ac.getCar(carIdx)
        if car == nil or car.isInPitlane or car.speedKmh >= slowCarSpeed then
            slowCarTimers[carIdx] = nil
        else
            slowCarTimers[carIdx] = timer + dt
        end
    end
end

function checkSlowCarPresence()
    if not raceStarted then
        for _, c in ac.iterateCars() do
            if c.speedKmh > 50 then
                raceStarted = true
                break
            end
        end
        if not raceStarted then
            slowCarTimers = {}
            return false
        end
    end

    if ac.getCar(0).isInPitlane then
        slowCarTimers = {}
        return false
    end

    local myProgress = ac.getCar(0).splinePosition
    local trackLen = SIM.trackLengthM
    local found = false

    for cari, carNo in ac.iterateCars.ordered() do
        if ac.getCar.ordered(cari-1) ~= nil then
            if carNo.speedKmh < slowCarSpeed and not carNo.isInPitlane then
                local dist = math.round((carNo.splinePosition - myProgress) * trackLen, 1)
                if dist < slowCarDistanceBehind and dist > -1 * slowCarDistanceAhead then
                    local carIdx = carNo.index
                    if slowCarTimers[carIdx] == nil then
                        slowCarTimers[carIdx] = 0
                    end
                    if slowCarTimers[carIdx] >= SLOW_CAR_CONFIRM_DELAY then
                        found = true
                    end
                end
            end
        end
    end

    return found
end

function penalties(dt)
    if currentFlags[4][1] == true and slowCarPenalties > -1 then
        code60Timing = code60Timing - dt
    else
        code60Timing = code60Timer
    end
    if code60Timing <= 0 and ac.getCar(0).speedKmh > 61 then
        code60Grace = code60Grace - dt
    else
        slowCarPenaltySet = false
        code60Grace = 0.5
    end
    if code60Grace <= 0 and not slowCarPenaltySet then
        slowCarPenaltySet = true
        ac.log("smite Thee")
        if slowCarPenalties == 0 then
            ac.sendChatMessage(ac.getCar(0):driverName() .. " violated a code60 zone at: " .. ac.lapTimeToString(SIM.currentSessionTime,true))
        elseif slowCarPenalties > 0 then
            physics.setCarPenalty(ac.PenaltyType.MandatoryPits, slowCarPenalties)
        end
    end
end

function flagHandler(dt)

    if ((trackProgress > noOvertake1_S) and (trackProgress < noOvertake1_E)) or ((trackProgress > noOvertake2_S) and (trackProgress < noOvertake2_E) or ((trackProgress > noOvertake3_S) and (trackProgress < noOvertake3_E))) or settingsOverride then
        currentFlags[1][1] = true
    else
        currentFlags[1][1] = false
    end

    if slowCarPenalties == -1 and slowCarConfirmed or settingsOverride then
        currentFlags[2][1] = true
    else
        currentFlags[2][1] = false
    end

    if shouldMeatball() or settingsOverride then
        currentFlags[3][1] = true
    else
        currentFlags[3][1] = false
    end

    if slowCarPenalties > -1 and slowCarConfirmed or settingsOverride then
        currentFlags[4][1] = true
    else
        currentFlags[4][1] = false
    end

    if (currentFlags[4][1] or currentFlags[2][1]) and enablePhysicsFlags == 1 then
        physics.overrideRacingFlag(ac.FlagType.Caution)
    else
        physics.overrideRacingFlag(ac.FlagType.None)
    end
end

function shouldMeatball()
    if (CAR.wheels[0].suspensionDamage > meatballThreshold) or
    (CAR.wheels[1].suspensionDamage > meatballThreshold) or
    (CAR.wheels[2].suspensionDamage > meatballThreshold) or
    (CAR.wheels[3].suspensionDamage > meatballThreshold) or
    CAR.wheels[0].isBlown or
    CAR.wheels[1].isBlown or
    CAR.wheels[2].isBlown or
    CAR.wheels[3].isBlown
    then
        return true
    else
        return false
    end
end


ac.onResolutionChange(function()
    windowWidth, windowHeight = ac.getSim().windowWidth,ac.getSim().windowHeight

        mirrorScale = windowHeight/1800


        vmirrorTop = (85/uiScale)
        vmirrorLeft = ((windowWidth/2)-(425.45525*mirrorScale)-2)/uiScale
        vmirrorBottom = ((213.78521*mirrorScale+83.3)/uiScale)
        vmirrorRight = ((windowWidth/2)+(425.45525*mirrorScale)+2)/uiScale
    flagsWindow = ui.ExtraCanvas(vec2(windowWidth,windowHeight))

end)

ui.registerOnlineExtra(ui.Icons.Flag, "BetterFlags Settings", function() return true end,
    function()
        settingsOverride = true

        tempSettings.flagWindowX = ui.slider("Flag Left/Right",tempSettings.flagWindowX, 0,1)
        tempSettings.flagWindowY = ui.slider("Flag Up/Down",tempSettings.flagWindowY, 0,1)



        if ui.modernButton("Apply Settings",vec2(200,50), ui.ButtonFlags.None, ui.Icons.Save) then
            betterFlagSettings = tempSettings
            return true
        end

    end,
    function(cancel)
        settingsOverride = false
end, ui.OnlineExtraFlags.Tool)



function script.drawUI()

ui.text(code60Timing .. " " .. code60Grace)

if settingsOverride then
    ui.setCursor(vec2(tempSettings.flagWindowX*windowWidth, tempSettings.flagWindowY*windowHeight))
else
    ui.setCursor(vec2(betterFlagSettings.flagWindowX*windowWidth, betterFlagSettings.flagWindowY*windowHeight))
end

flagsWindow:clear()
flagsWindow:update(function(dt)
        local blanks = 0
    for i = 1, #currentFlags do

        if currentFlags[i][1] then
            ui.drawImage(currentFlags[i][2],vec2((120*(i-blanks)),0),vec2(256+(120*(i-blanks)),256))
        else
            blanks = blanks + 1
        end
    end
end)
ui.image(flagsWindow, vec2(windowWidth,windowHeight))

ui.setCursor(vec2(0,0))




end
