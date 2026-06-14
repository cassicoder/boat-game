--!strict
-- BoatOwnershipSystem
-- The boat is driven on the DRIVER'S client (that's what makes it smooth and stops
-- the server/client tug-of-war that left it bouncing in place). For that, the client
-- must own the hull's physics. Each frame we make sure every boat is network-owned by
-- whoever is sitting in its seat, and handed back to the server (nil) when empty. We
-- only call SetNetworkOwner on an actual change, so there's no per-frame thrashing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Components = require(ReplicatedStorage.Shared.Components)

return function(world, _state)
	for id, boat in world:query(Components.Boat) do
		if boat.model.Parent == nil then
			world:despawn(id)
			continue
		end

		local hull = boat.hull
		if hull.Anchored then
			continue
		end

		-- who SHOULD own it: the seated player, else the server (nil)
		local desired: Player? = nil
		local occ = boat.seat.Occupant
		if occ then
			desired = Players:GetPlayerFromCharacter(occ.Parent)
		end

		local current: Player? = nil
		local okGet = pcall(function()
			current = hull:GetNetworkOwner()
		end)
		if okGet and current ~= desired then
			pcall(function()
				if hull:CanSetNetworkOwnership() then
					hull:SetNetworkOwner(desired)
				end
			end)
		end
	end
end
