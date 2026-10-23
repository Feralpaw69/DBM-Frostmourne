local mod	= DBM:NewMod("Razuvious", "DBM-Naxx", 4)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20221016184543")
mod:SetCreatureID(16061)

mod:RegisterCombat("combat_yell", L.Yell1, L.Yell2, L.Yell3, L.Yell4)

mod:RegisterEventsInCombat(
	"SPELL_CAST_SUCCESS 55543 29107 29060 29061 9250607 9250609 26613 9250606 9250608 9250696",
	"SPELL_AURA_APPLIED 605 9250609 9250608",
	"SPELL_AURA_REMOVED 9250609 9250608",
	"UNIT_DIED"
)

local warnShoutNow		= mod:NewSpellAnnounce(29107, 1)
local warnShoutSoon		= mod:NewSoonAnnounce(29107, 3)
local warnShieldWall	= mod:NewAnnounce("WarningShieldWallSoon", 3, 29061, nil, nil, nil, 29061)
local warnKnife			= mod:NewTargetNoFilterAnnounce(9250609, 2) -- Frostmourne custom
local yellKnife			= mod:NewYell(9250609, "Jagged Knife on me")

local timerShout		= mod:NewNextTimer(15, 29107, nil, nil, nil, 2) -- Whitemane PTR buff notes say it should be 12, but was consistently 15s in the vod
local timerTaunt		= mod:NewCDTimer(20, 29060, nil, nil, nil, 5, nil, DBM_COMMON_L.TANK_ICON)
local timerShieldWall	= mod:NewCDTimer(20, 29061, nil, nil, nil, 5, nil, DBM_COMMON_L.TANK_ICON)
local timerMindControl	= mod:NewBuffActiveTimer(60, 605, nil, nil, nil, 6)
local timerKnifeCD		= mod:NewNextTimer(10, 9250609, nil, nil, nil, 3) -- Frostmourne custom: 25-man 35.5 then every 10; 10-man 15.7 then every 25
local timerDisciplinaryCD = mod:NewNextTimer(15, 9250696, nil, nil, nil, 2) -- 10-man only (in 25-man it comes together with Disrupting Shout): 15.7, then every 15
local timerUnbalancingCD = mod:NewCDTimer(30, 26613, nil, "Tank|Healer", nil, 5, nil, DBM_COMMON_L.TANK_ICON) -- Frostmourne log 2026-10-06: 29.9 / 60.0 / 90.0

mod:AddRangeFrameOption(12, 9250696) -- Disciplinary Shout (Frostmourne custom)
mod:SetUsedIcons(8)
mod:AddSetIconOption("SetIconOnKnife", 9250609, true, false, {8})

-- Jagged Knife: the cast names the target ~2s before the bleed lands; the bleed lasts ~5s (logs 2026-10-06 to 10-10)
local knifeMarked
local function ClearKnifeIcon(self, name)
	if name and knifeMarked == name then
		self:SetIcon(name, 0)
		knifeMarked = nil
	end
end

local function KnifeTarget(self, name)
	if not name then return end
	if self.Options.SetIconOnKnife then
		self:Unschedule(ClearKnifeIcon)
		if knifeMarked and knifeMarked ~= name then
			self:SetIcon(knifeMarked, 0)
		end
		knifeMarked = name
		self:SetIcon(name, 8)
		self:Schedule(9, ClearKnifeIcon, self, name) -- safety clear if the bleed never lands or its removal is missed
	end
	if name == UnitName("player") and self:AntiSpam(3, "knifeYell") then
		yellKnife:Yell()
	end
end

function mod:OnCombatStart(delay)
	if self:IsDifficulty("heroic10") then -- log 2026-10-08
		timerKnifeCD:Start(15.5 - delay)
		timerDisciplinaryCD:Start(15.5 - delay)
	else
		timerKnifeCD:Start(35.5 - delay)
	end
	timerUnbalancingCD:Start(30 - delay)
	if self.Options.RangeFrame then
		DBM.RangeCheck:Show(12)
	end
	if self:IsDifficulty("normal25", "heroic25") then -- Frostmourne raid reports as heroic25; log 2026-10-06: shout every 15.0-15.5
		timerShout:Start(15 - delay)
		warnShoutSoon:Schedule(10 - delay)
	else
		timerShout:Start(25 - delay)
		warnShoutSoon:Schedule(20 - delay)
	end
end

function mod:OnCombatEnd()
	if self.Options.RangeFrame then
		DBM.RangeCheck:Hide()
	end
	if knifeMarked then
		self:SetIcon(knifeMarked, 0)
		knifeMarked = nil
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	local spellId = args.spellId
	if args:IsSpellID(55543, 29107, 9250607, 9250606) then -- 9250606: 10-man  -- Disrupting Shout (9250607: Frostmourne custom)
		warnShoutNow:Show()
		if self:IsDifficulty("normal25", "heroic25") then
			timerShout:Start()
			warnShoutSoon:Schedule(10)
		else
			timerShout:Start(25)
			warnShoutSoon:Schedule(20)
		end
	elseif spellId == 29060 then -- Taunt
		timerTaunt:Start(20, args.sourceGUID)
	elseif spellId == 29061 and self:AntiSpam(2, 1) then -- ShieldWall
		timerShieldWall:Start(20, args.sourceGUID)
		warnShieldWall:Schedule(15)
	elseif spellId == 9250609 or spellId == 9250608 then -- Jagged Knife (Frostmourne custom; 9250608: 10-man)
		timerKnifeCD:Start(self:IsDifficulty("heroic10") and 25 or 10)
		KnifeTarget(self, args.destName)
	elseif spellId == 9250696 and self:IsDifficulty("heroic10") then -- Disciplinary Shout
		timerDisciplinaryCD:Start()
	elseif spellId == 26613 then -- Unbalancing Strike
		timerUnbalancingCD:Start()
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == 605 and args:IsSrcTypePlayer() then -- Mind Control
		timerMindControl:Start(nil, args.sourceName)
	elseif args:IsSpellID(9250609, 9250608) then -- Jagged Knife (Frostmourne custom)
		warnKnife:Show(args.destName)
		if knifeMarked ~= args.destName then
			KnifeTarget(self, args.destName)
		end
	end
end

function mod:SPELL_AURA_REMOVED(args)
	if args:IsSpellID(9250609, 9250608) then -- Jagged Knife bleed gone: remove the mark
		ClearKnifeIcon(self, args.destName)
	end
end

function mod:UNIT_DIED(args)
	local guid = args.destGUID
	local cid = self:GetCIDFromGUID(guid)
	if cid == 16803 then--Deathknight Understudy
		timerTaunt:Stop(args.destGUID)
		timerShieldWall:Stop(args.destGUID)
	end
end
