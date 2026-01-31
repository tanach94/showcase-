-- so this is my script and like 200 attempt to get hidden devs role, i made this and for like 4 days. Jozinn93 on roblox, dc masternamedjoe
local itemMover = {}

local Camera = workspace.CurrentCamera

local getMousePointRayCastParams = RaycastParams.new()
local collidingOverLapParams = OverlapParams.new()

local myMeta = nil

local AXIS_DIRECTIONS = {
	X = Vector3.xAxis,
	Y = Vector3.yAxis,
	Z = Vector3.zAxis
}

local clientPaths = require(game:GetService("ReplicatedStorage").Modules.Utility.ClientPaths)
local utilityModule = require(script.Parent.Utility)
local inputManager = require(clientPaths.ReplicatedStorage.Modules.Utility.InputManager)
local viewPortPointToRay = require(clientPaths.ReplicatedStorage.Modules.Utility.ViewportPointToRay)
local troveModule = require(clientPaths.Shared.Utility.Trove) :: any

local assetsPlotSystem = clientPaths.ReplicatedStorage.Assets.PlotSystem
local studMoveSound = assetsPlotSystem.Sounds.StudMove

local inputSignal = clientPaths.UserInputService.TouchEnabled and "Touch" or "MouseButton1"

-- Smooth transparency fade.
local function tweenTransparencyPart(Part:BasePart, Transparency : number)
	local tween = clientPaths.TweenService:Create(
		Part,
		TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
		{Transparency = Transparency}
	)
	tween:Play()
end

-- This function, does that, when i start moving any object, what have PrimaryPart, it will snap moving axis to snappingNumber.
local function SnapNumber(number: number, customSnapper: number?): number
	local snap = customSnapper or utilityModule.snappingNumber
	return math.round(number / snap) * snap
end

-- This, takes string. And returns only if first letter is the same as ending letter.
local function GetAxisName(name: string): string
	return name:sub(1, 1)
end

-- To collide objects, the moving object is inside, i'm using GetPartsInPart function. 
local function Colliding(self: utilityModule.newPlotType)
	local primary = self.Object.PrimaryPart

	local parts = workspace:GetPartsInPart(self.Object.PrimaryPart, collidingOverLapParams)
	return #parts > 0
end

-- Here i'm checking every axis of border, and it's edge. And return an clamped axis inside edges. So my moving part can't go outside Barrier.
local function plotBorderedPosition(self : utilityModule.newPlotType, movingVector : Vector3)
	local borderedPosition : Vector3 = self.myPlot.Barrier.CFrame:PointToObjectSpace(movingVector)
	local plotCorners = (self.myPlot.Barrier.Size / 2) -- i'm using here half size of part, part have 10 size for example, half is 5. -5 is one edge, 10 is ending edge.

	local vectorFull = {}

	local function clampVectorCoordination(coordinationName : string)
		local coordinationToClamp = plotCorners[coordinationName]
		vectorFull[coordinationName] = math.clamp(borderedPosition[coordinationName], -coordinationToClamp, coordinationToClamp)
	end

	for coordinationName, vector in pairs(AXIS_DIRECTIONS) do 
		clampVectorCoordination(coordinationName)
	end
	
	-- i'm using PointToWorldSpace because i need know the axis from part perspective, not world, so when i give player plot, its from plot.
	return self.myPlot.Barrier.CFrame:PointToWorldSpace(Vector3.new(vectorFull.X, vectorFull.Y, vectorFull.Z))
end

-- Creating arrows i will click on to move with part.
local function CreateDragArrow(self, axis: string, isOpposite: boolean): BasePart
	local arrow = Instance.new("Part")
	arrow.Name = axis .. (isOpposite and "2" or "") -- here, making sure, to spawn arrow on -axis and axis. Not only one side of axis.
	arrow.Color = utilityModule.Arrows.Colors[axis] or Color3.new(1, 1, 1)
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.Parent = self.Object

	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 50
	
	cd.MouseHoverEnter:Connect(function()
		self.Arrows[arrow].hovering = true -- storing here this, so when i click, i look for arrows, and check what arrow i'm hovering on, and clicking at the same time.
	end)
	
	cd.MouseHoverLeave:Connect(function()
		self.Arrows[arrow].hovering = false
	end)
	
	cd.Parent = arrow

	self.Arrows[arrow] = {hovering = false, held = false}
	self.editingTrove:Add(arrow) -- adding arrow to cleanUp later.
	return arrow
end

local function PrepareArrows(self)
	local primary : BasePart = self.Object.PrimaryPart
	local halfSize = primary.Size / 2

	local ARROW_OFFSET = 5
	local ARROW_SIZE = Vector3.new(1, 1, 5)

	for axis, unitVector in pairs(AXIS_DIRECTIONS) do -- this loop is because of -axis and axis, so arrow x has -x and x around moving object
		for _, sideMult in ipairs({1, -1}) do
			local isOpposite = (sideMult == -1)
			local arrow = CreateDragArrow(self, axis, isOpposite)

			local localOffset = unitVector * (halfSize[axis] + ARROW_OFFSET) * sideMult -- this offset is for arrow, to go from primaryPart specific axis depending on it's size. So arrows are not inside moving object.

			local worldPos = primary.CFrame:PointToWorldSpace(localOffset) -- making sure, 0,0,0 is from primary.

			arrow.CFrame = CFrame.lookAt(worldPos, worldPos + (primary.CFrame:VectorToWorldSpace(unitVector * sideMult))) -- making sure to arrow look at primary part. Also using VectorToWorldSpace, for primary Rotation.
			arrow.Size = ARROW_SIZE
		end
	end
end

local function setOffset(self : utilityModule.newPlotType, coordination : string) : Vector3 -- this is offset when i'm moving object using arrows, so the object position is - or + offset from part to the arrow.
	local partAndArrowDistance = (self.Object.PrimaryPart.Position - self.holdingArrow.Position).Magnitude
	local axis = GetAxisName(coordination)

	local negatives = {
		X2 = true,
		Z2 = true,
		Y2 = true,
	}

	local subtractor = negatives[coordination] and 1 or -1
	return AXIS_DIRECTIONS[axis] * (partAndArrowDistance * subtractor)
end

local function getRayPlaneIntersection(rayOrigin: Vector3, rayDirection: Vector3, planePoint: Vector3, planeNormal: Vector3): Vector3? -- this function, i didnt create it on my own, this one, is different than mouse hit, it creates an infinite part looking at me and the mouse overall is smooth, when i hit sky, its normal.
	local denominator = planeNormal:Dot(rayDirection)

	if math.abs(denominator) > 0.0001 then
		local t = (planePoint - rayOrigin):Dot(planeNormal) / denominator
		if t >= 0 then
			return rayOrigin + rayDirection * t
		end
	end
	
	return nil
end

local function MoveObject(self: utilityModule.newPlotType)
	local movingArrow = self.holdingArrow
	if not movingArrow then return end

	local primary = self.Object.PrimaryPart
	local axisName = GetAxisName(movingArrow.Name) -- getting clear axis, no X2 or Y2 or Z2 just X 
	local moveAxis = AXIS_DIRECTIONS[axisName] 

	local mouseLocation = clientPaths.UserInputService:GetMouseLocation()
	local unitRay = Camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local planeNormal = (Camera.CFrame.Position - primary.Position).Unit

	local intersection = getRayPlaneIntersection(unitRay.Origin, unitRay.Direction, primary.Position, planeNormal) -- getting the infinite part on screen, so mouse movement in game is smooth.

	if intersection then
		local localMousePos = primary.CFrame:PointToObjectSpace(intersection) -- this PointToObjectSpace, im doing this because of relativity, to the primary part. When i use this one function, it starts from the part, and no matter what, (1,0,0) is from his origin, then i can convert it to worldspace later.

		local offset = setOffset(self, movingArrow.Name)[axisName]
		local snappedLocalValue = SnapNumber(localMousePos[axisName] + offset)

		local localMoveVector = Vector3.new(
			axisName == "X" and snappedLocalValue or 0,
			axisName == "Y" and snappedLocalValue or 0,
			axisName == "Z" and snappedLocalValue or 0
		)

		local worldTargetPos = primary.CFrame:PointToWorldSpace(localMoveVector)
		local boundedPos = plotBorderedPosition(self, worldTargetPos)

		self.Object:PivotTo(CFrame.new(boundedPos) * primary.CFrame.Rotation)
		
		if not studMoveSound.IsPlaying then
			studMoveSound:Play()
		end
	end
end

local function Loop(self: utilityModule.newPlotType) -- creating a lloop for moving object
	if not self.looping then return end
	if not self.Object then return end 
	local primary = self.Object.PrimaryPart

	self.troves[self.Object]:Add(inputManager.Signals["MouseMoved"]:Connect(function() -- getting from input manager, when mouse moved.
		local ray = viewPortPointToRay.Get3DMousePointToRay(getMousePointRayCastParams) -- getting the mouse position from 2D, converting to 3D using Point to ray camera. and also using raycast after that and checking hitted objects.
		local colliding = Colliding(self)

		if colliding then
			self.Object.PrimaryPart.Color = Color3.fromRGB(255, 0, 0)
			self.canPlace = false
		else
			self.canPlace = true
			self.Object.PrimaryPart.Color = Color3.fromRGB(102, 255, 0)
		end
		
		if not ray then return end

		self.mousePosition = ray.Position
		self.movingObjectPosition = primary.Position
		MoveObject(self)
	end),"Disconnect", "MovementLoop")
end

local function Rotate(self: utilityModule.newPlotType)
	self.Object:PivotTo(self.Object:GetPivot() * CFrame.Angles(math.rad(90),0,0))
end

function itemMover.PrepareForMoving(self: utilityModule.newPlotType, Object: Model) -- main function
	if not self.troves[Object] then
		self.Object = Object
		Object.PrimaryPart.Transparency = .8
		self.Arrows = {}
		self.troves[Object] = troveModule.new()
		PrepareArrows(self)

		getMousePointRayCastParams.FilterType = Enum.RaycastFilterType.Include
		getMousePointRayCastParams.FilterDescendantsInstances = {workspace}

		collidingOverLapParams.FilterType = Enum.RaycastFilterType.Include
		collidingOverLapParams.FilterDescendantsInstances = {self.myPlot.Objects}

		self.troves[Object]:Add(inputManager.Signals[inputSignal]:Connect(function(params) -- mouse began/ended
			if params.fired then
				for arrow, state in pairs(self.Arrows) do
					if state.hovering then

						state.held = true

						self.holdingArrow = arrow
						self.looping = true

						Loop(self)

						inputManager.inputChangedAllowed = true

						if self.deviceType then
							Camera.CameraType = Enum.CameraType.Scriptable
						end

                        tweenTransparencyPart(arrow, .5)
						break
					end
				end
			else
				if self.holdingArrow then
					tweenTransparencyPart(self.holdingArrow, 0)
					
					local state = self.Arrows[self.holdingArrow]
					if state then state.held = false end

					self.looping = false
					self.holdingArrow = nil
					self.heartBeat = nil 

					if self.troves[Object] then
						self.troves[Object]:Remove("MovementLoop")
					end

					inputManager.inputChangedAllowed = nil
					if self.deviceType then
						Camera.CameraType = Enum.CameraType.Custom
					end
				end
			end
		end))

		self.troves[Object]:Add(inputManager.Signals["R"]:Connect(function(params) -- key R pressed
			if params.fired then
				Rotate(self)
			end
		end))

		self.troves[Object]:Add(inputManager.Signals["X"]:Connect(function(params) -- key X pressed, ending edit mode
			self:EndEditMode()
		end))
	end
end

inputManager.Signals[inputSignal]:Connect(function(params) -- clicking on item, to start editing in my plot. then X to cancel moving.
	if itemMover.myMeta and params.fired then
		local plot = itemMover.myMeta.myPlot
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {plot}
		

		local clickResult : RaycastResult = viewPortPointToRay.Get3DMousePointToRay(params) -- basically checks if im clicking on any part ye
		if clickResult then
			local clickInstance = clickResult.Instance
			local model = clickInstance.Parent
			if model:IsA("Model") then
				if model.Parent == plot then
					itemMover.myMeta:StartEditMode(model)
				end
			end
		end
	end
end)

return itemMover
