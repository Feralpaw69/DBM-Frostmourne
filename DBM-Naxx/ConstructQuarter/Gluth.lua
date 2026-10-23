local mod	= DBM:NewMod("Gluth", "DBM-Naxx", 2)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20220806123502")
mod:SetCreatureID(15932)

mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 28371 54427 25646",
	"SPELL_AURA_APPLIED_DOSE 25646",
	"SPELL_AURA_REMOVED 28371 54427 25646",
	"SPELL_CAST_SUCCESS 28375 25646"
)

local warnEnrage		= mod:NewTargetNoFilterAnnounce(54427, 3, nil , "Healer|Tank|RemoveEnrage", 2)
local warnDecimateSoon	= mod:NewSoonAnnounce(28374, 2)
local warnDecimateNow	= mod:NewSpellAnnounce(28374, 3)

local specWarnEnrage	= mod:NewSpecialWarningDispel(54427, "RemoveEnrage", nil, nil, 1, 6)

local timerEnrage		= mod:NewBuffActiveTimer(8, 54427, nil, nil, nil, 5, nil, DBM_COMMON_L.ENRAGE_ICON)
local timerEnrageCD		= mod:NewCDTimer(30, 54427, nil, nil, nil, 5)
local timerDecimate		= mod:NewCDTimer(90, 28374, nil, nil, nil, 2)
local timerMortalWoundCD = mod:NewCDTimer(8, 25646, nil, "Tank|Healer", nil, 5, nil, DBM_COMMON_L.TANK_ICON) -- Frostmourne logs: every 8 on 25-man, every 10 on 10-man (first at 10)
-- Mortal Wound stacks on the tank (log 2026-10-10: one stack per hit, each refreshes the 15s debuff; tanks swapped at 6-7 stacks)
local warnMortalWound		= mod:NewStackAnnounce(25646, 2, nil, "Tank|Healer")
local specWarnMortalWound	= mod:NewSpecialWarningStack(25646, nil, 5, nil, nil, 1, 6)
local specWarnMortalTaunt	= mod:NewSpecialWarningTaunt(25646, nil, nil, nil, 1, 2)
local timerMortalWound		= mod:NewTargetCountTimer(15, 25646, nil, "Tank|Healer", nil, 5, nil, DBM_COMMON_L.TANK_ICON)
local enrageTimer		= mod:NewBerserkTimer(360)

function mod:OnCombatStart(delay)
	enrageTimer:Start(360 - delay)
	if self:IsDifficulty("heroic10") then
		timerMortalWoundCD:Start(10 - delay) -- logs 2026-10-08/10: first Mortal Wound at 10.0 (and 30.1 once)
	end
	timerEnrageCD:Start(30 - delay)
	if self:IsDifficulty("normal25") then
		timerDecimate:Start(90 - delay)
		warnDecimateSoon:Schedule(80 - delay)
	else
		timerDecimate:Start(105 - delay)
		warnDecimateSoon:Schedule(95 - delay)
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == 25646 then -- Mortal Wound stack
		local amount = args.amount or 1
		timerMortalWound:Stop()
		timerMortalWound:Start(nil, amount, args.destName)
		warnMortalWound:Show(args.destName, amount)
		if args:IsPlayer() then
			if amount >= 5 then
				specWarnMortalWound:Show(amount)
				specWarnMortalWound:Play("stackhigh")
			end
		elseif amount >= 5 and self:IsTank() and not DBM:UnitDebuff("player", args.spellName) then
			specWarnMortalTaunt:Show(args.destName)
			specWarnMortalTaunt:Play("tauntboss")
		end
		return
	end
	if args:IsSpellID(28371, 54427) then
		if self.Options.SpecWarn54427dispel then
			local class = self:UnitClass()
			if class == "HUNTER" or class == "ROGUE" then
				specWarnEnrage:Play("dispelboss")
			else
				specWarnEnrage:Play("enrage")
			end
			specWarnEnrage:Show(args.destName)
		else
			warnEnrage:Show(args.destName)
		end
		timerEnrage:Start()
		timerEnrageCD:Start()
	end
end

mod.SPELL_AURA_APPLIED_DOSE = mod.SPELL_AURA_APPLIED

function mod:SPELL_AURA_REMOVED(args)
	if args.spellId == 25646 then
		timerMortalWound:Stop()
		return
	end
	if args:IsSpellID(28371, 54427) then
		timerEnrage:Stop()
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args.spellId == 25646 then -- Mortal Wound
		timerMortalWoundCD:Start(self:IsDifficulty("heroic10") and 10 or 8) -- 10-man logs: every 10.0
	elseif args.spellId == 28375 and self:AntiSpam(20) then
		if self:IsDifficulty("normal25") then
			warnDecimateNow:Show()
			timerDecimate:Start()
			warnDecimateSoon:Schedule(80)
		else
			warnDecimateNow:Show()
			timerDecimate:Start(105)
			warnDecimateSoon:Schedule(95)
		end
	end
end
