;;; For communication and BDI architecture

__includes ["communication.nls" "bdi.nls"]



globals [dead-trees saved-trees fires-left-in-sim units-destroyed]
breed [ units ]
breed [ scouters ]
breed [ trees ]
breed [ fires ]
breed [ fires-out ]

patches-own [ signal ]
units-own [water beliefs intentions incoming-queue]
scouters-own [beliefs intentions incoming-queue]


to setupSimulationEnvironment
  ;; (for this model to work with NetLogo's new plotting features,
  ;; __clear-all-and-reset-ticks should be replaced with clear-all at
  ;; the beginning of your setup procedure and reset-ticks at the end
  ;; of the procedure.)
  __clear-all-and-reset-ticks
  ask patches [set signal 0]
  set fires-left-in-sim number-of-fires
  set dead-trees 0
  set saved-trees 0
  set units-destroyed 0
  start-signal
  create-base
  setup-trees
  setup-units
  setup-scouters
end

;;; Create the base for refueling/water supplies
;;; Simply ask the specific patch to change color
to create-base
  ask patch 0 0 [set pcolor red]
end

;;; start signaling. The signal is a property of the patch (patch variable)
;;; Its value is proportional to its distance from base (patch 0 0)
to start-signal
  ask patches [set signal distancexy-nowrap 0 0]
end


;;;;;;;;;;;;; Setting up the various "agents" in the environment
;;; setting up trees
to setup-trees
   create-trees tree-num [
      set shape "tree"
      rand-xy-co
      set color green
      ]
end

;;; setting up units
;;; creates the units that detect and extinguish fires
to setup-units
   create-units fire-units-num [
      set shape "fire-unit"
      set color blue
      set water initial-water
      setxy (random 4 + random -4) (random 4 + random -4)
      set intentions [["find-target-fire" "false"]]
      set beliefs []
      set incoming-queue []
      ]
end

to setup-scouters
  create-scouters scouter-num [
     set shape "scouter"
     set color yellow
     setxy (random 4 + random -4) (random 4 + random -4)
     set intentions [["look-for-fires" "false"]]
     set beliefs []
     set incoming-queue []
  ]
end
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Running the experiment until not more fires are left for simulation and
;;; no more fires are still buring.
;;; Asks the units to execute behaviour and asks fire to spread
to run-experiment
  if fires-left-in-sim <= 0 and not any? fires [stop]
  start-fire-probability
  ask units [without-interruption [units-behaviour]]
  ask fires [without-interruption [fire-model-behaviour]]
  ask scouters [without-interruption [scouter-behaviour]]
  tick
end


;;; starts randonly a fire according to a probability (10%)
;;; This give a model in which fire spots start at different execution times
to start-fire-probability
if not any? trees [set fires-left-in-sim 0 stop]
if fires-left-in-sim > 0
  [
  let p random 100
  if p < 10 and any? trees [
    ask one-of trees [ignite]
    set fires-left-in-sim fires-left-in-sim - 1]
    ]

end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FIRE MODEL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; how fire spreads
;;; Fire burns for a certain period after which thre "tree" on fire dies
;;; the time is indicated by the color of the patch, that fades in each cycle.
;;; After a number of cycles, when its color is near to black, the tree dies.
to fire-model-behaviour
 without-interruption [
 if any? trees-on neighbors [ask one-of trees-on neighbors [ ignite ]]
 if any? units-on patch-here [ask one-of units-on patch-here [die] set units-destroyed units-destroyed + 1]
 set color color - 0.01
 if color < red - 4 [set dead-trees dead-trees + 1  die]

 ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; starts a fire in a tree location
to ignite
  set breed fires
  set shape "tree"
  set color red
end

;;; fire in a tree location is extinguished.
to extinguish
  set breed fires-out
  set shape "tree"
  set color yellow
end
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;; THE AGENTS ;;;;;;;
;;; unit behaviour consists of two layers. The reactive an pro-active. The reacitive layer
;;; is responsible for extinguishing fire when it is detected and for reloading the agent with water,
;;; if it is necessary. The Proactive layer is repsonsible for receiving messages setting targets to extinguish etc.

to units-behaviour
  if reactive-behaviour-unit [stop] ;; Just to make sure that only one action gets fired.
  collect-msg-update-intentions ;; Read through all the messages that were received, then update the intentions
  execute-intentions  ;; Try to realise intentions
end

;;; Simple reactive behaviour in order to put out any fires in area.
;;; If this returns true, it means that the agent has perfromed an action in this cycle
;;; and thus can do no other action.
to-report reactive-behaviour-unit
  if detect-fire and have-water [put-out-fire report true]
  if need-water and at-base [service-unit report true]
  if need-water and detect-obstacle [avoid-obstacle report true]
  if need-water and not at-base and not detect-obstacle [move-towards-base report true]
  report false
end

;; Collect messages looks at all the messages, and may change the agent's beliefs about the world
;; The beliefs may have changed and so we should update intentions
to collect-msg-update-intentions
let msg 0
let performative 0
while [not empty? incoming-queue]
  [
   set msg get-message
   set performative get-performative msg
   ;Create the belief that information about a new fire has arrived
   if performative = "inform" [ add-belief create-belief "information" msg]
   ;Create the belief that a new fire has to be put out
   if performative = "proceed" [ add-belief create-belief "fire" msg ]
   ]
 update-intentions
end

;; Update intentions with respect to beliefs about the world
to update-intentions
  if exist-beliefs-of-type "fire" and current-intention = "find-target-fire" ;; if there is at least one belief about a fire location
  [
     let fire-belief read-first-belief-of-type "fire"
     let fire-message belief-content fire-belief
     let fire-location get-content fire-message

     let coords item 1 fire-location  ;; get the second element of the list

     ;; In response to the fire, we need to:
     ;; 1.Send confirmation that we are heading towards the location of the fire
     ;; 2. move towards the location of the fire
     ;; 3. once arrived, extinguish the fire
     ;; So we add intentions for each of these behaviours
     ;; Note that the intentions are pushed onto the stack in reverse order so that they are popped off of the stack in the correct order
     add-intention "put-out-fire" "fire-out" ;;2. extinguish the fire, achieved when the fire is out
     add-intention (word "move-towards-dest " coords) (word "at-dest " coords) ;; 1. move towards the location of the fire, achieved when we arrive
     add-intention "do-nothing" timeout_expired 5 ;; wait 5ms before starting (this is to help the visualisation only)
     add-intention "confirm-to-scout" "true"
  ]

  if exist-beliefs-of-type "information" and current-intention = "find-target-fire" ;; if there is at least one belief about a fire location
  [
     ;;In response to new information regarding fires we need to:
     ;;1.Inform the scout our position and availability
     ;;2.Wait for a decision from the scout
     add-intention "find-target-fire" "false"
     add-intention "inform-scout" "true"
  ]
end


;;; If no current beliefs about a target fire then the unit does nothing
to find-target-fire
end

;;; broadcasting to the reporting scout that
;;; we are heading towards the fire
to confirm-to-scout
  ;;Get the content of the belief and reply
  ;; with the position were the unit is heading
  let fire-belief get-belief "fire"
  let msg belief-content fire-belief
  let msg-content get-content msg
  let fire-location last msg-content

  ;;Send confirmation message
  let reply create-message "proceeding"
  set reply add-content fire-location reply
  set reply add-receiver get-sender msg reply

  send reply
end

;;; send a response to a fire reporting scout
;;;about the ground units location.
to inform-scout
  ;;Get the content of the belief and reply
  ;; with the distance from the fire
  let respond-belief get-belief "information"
  let msg belief-content respond-belief
  let msg-content get-content msg
  let fire-location last msg-content

  let distance-from-fire report-distance-from-fire fire-location

  ;;Send message
  let reply create-message "available"
  set reply add-content distance-from-fire reply
  set reply add-receiver get-sender msg reply

  send reply
end

;;Use it to calculate the distance from a reported fire
to-report report-distance-from-fire [location]
  let distance-x first location ;; x coordinate of location
  let distance-y last location ;; y coordinate of location
  let final-distance (abs (xcor - distance-x)) + (abs (ycor - distance-y))
  report final-distance
end

;
;; Returns the belief of the closest fire location
to-report closest-fire-location
  let fire-beliefs beliefs-of-type "fire" ;; get all the beliefs relating to fire locations

  let closest-belief first fire-beliefs ;; get the first belief in the list
  let closest-location last closest-belief ;; initialise closest location with the location in first belief in the list
  let closest-x first closest-location ;; x coordinate of location
  let closest-y last closest-location ;; y coordinate of location
  let closest-distance (abs (xcor - closest-x)) + (abs (ycor - closest-y)) ;; calculate Manhatten distance to current closest

  ;;iterate through the list to find the closest
  foreach fire-beliefs[
    let new-location last ? ;; ? represents the current belief in the list we are looking at. "last" gets the coordinate of the fire from the belief.
    let new-x first new-location ;; x coordinate of location
    let new-y last new-location ;; y coordinate of location

    ;; calculate distances - here we use Manhatten distance. Note that the world wraps both horizontally and vertically.
    ;; x coordinates range from -25 to 25. y coordinates range from -17 to 17.

    let x-distance (abs (xcor - new-x))

    ;; if the x-distance is more than 25 then it is closer to wrap through the walls, so use this distance
    if (x-distance > 25)[
      set x-distance (51 - (abs (xcor - new-x)))
    ]


    let y-distance (abs (ycor - new-y))

    ;; if the y-distance is more than 17 then it is closer to wrap through the walls, so use this distance
    if (y-distance > 17)[
      set y-distance (35 - (abs (ycor - new-y)))
    ]


    let new-distance (x-distance + y-distance)

    if (new-distance < closest-distance)[ ;; the new location is closer, update closest to be the new location
      set closest-location new-location
      set closest-belief ?
      set closest-x new-x
      set closest-y new-y
      set closest-distance new-distance
    ]
  ]

  report closest-belief ;; closest-belief is now the belief that represents the fire location closest to the agent
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; scouter behaviour
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to scouter-behaviour
  ;;Scout should leave after finding an available unit to put out the fire
  execute-intentions
end

;;;; scouter plans
to look-for-fires
  ;; To look for fires we need to:
  ;; 1. search for a fire until we find a new fire
  ;; 2. send a message to all other agents about the location of the fire and wait until one responds
  ;; 3. Select an appropiate candidate and the go back to scounting
  ;; So we add intentions for each of these behaviours
  ;; Note that the intentions are pushed onto the stack in reverse order so that they are popped off of the stack in the correct order
  add-intention "select-candidate" "true" ;; 3 delegate task
  add-intention "inform-all" "found-available-unit" ;; 2.broadcast until a unit is found
  add-intention "search-fire" "detected-new-fire" ;; 1.seacrh for a fire until a new and unattended on is found
 end

;;; Reactive: move randomly, avoid obstacles
to search-fire
   if detect-obstacle-scouter [avoid-obstacle stop]
   if true [scouter-random-move stop]
end

;;Select ground unit based
;;on distance from the reported fire
to select-candidate
   let msg 0
   let performative 0
   ;;Analize all receiving messages
   if (not empty? incoming-queue)
   [;;Set receiver priority to the first message
    set msg get-message
    set performative get-performative msg
    if (performative = "available")
         [ let min-distance 0
           let candidate 0
           set min-distance get-content msg
           set candidate get-sender msg

        while [not empty? incoming-queue]
         [ ;;If a new unit with a smaller distance
           ;;from the fire is found
           ;;Update receiver
           set msg get-message
           set performative get-performative msg
           if performative = "available"
             [
              let tmp get-content msg
              if (tmp < min-distance)
                [
                 set min-distance tmp
                 set candidate get-sender msg
                 ]
              ]
           ]
        ;;Delegate task to the chosen unit
        let reply create-message "proceed"
        set reply add-content fire-location-s reply
        set reply add-receiver candidate reply
        send reply
     ]
   ]
end

;;; broadcasting info about the location of a fire.
to inform-all
  ;;In the current implementation there is no need
  ;;To keep broadacsting if the there are pending messages
  ;;As this will mean that availble units have been found
  if(empty? incoming-queue)
  [let msg create-message "inform" ;; create a message with performative "inform"
   set msg add-content fire-location-s msg ;; set the content of the message to the location of the fire
   broadcast-to units msg]
end

;;Used to establish when to stop looking for a fire
to-report detected-new-fire
  ;;Get the current found fire location
  let coords item 1 fire-location-s
  let msg 0
  let performative 0
  let msg-fire 0
  ;;If it has been detected and
  ;;There is no-one else at tha location
  ifelse (detect-fire) and (at-dest coords)
     [ ;;Check to see if the fire was broadcasted before
       ;;Use the last confirmation message recived
       ;;From the last delegated ground unit
       ifelse (not empty? incoming-queue)
       [ set msg get-message-no-remove
         set performative get-performative msg
         set msg-fire get-content msg
         ifelse (performative = "proceeding") and (coords = msg-fire)
          [report false]
          [remove-msg report true]
       ]
       ;;If no mesage received return report fire
       [report true]
     ]
    ;;If fire is new or not attend it,broadcast it
    [report false]
end

;;Check to see if there are pending messages
;;Or if the current fire has burned out
;;Used to establish when to stop broadcasting
;;the location of the fire
to-report found-available-unit
  ifelse (not empty? incoming-queue) or (fire-out)
    [report true]
    [report false]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; simple data structure for fires
;;; ("fire" (x y))
;;; returns a list that indicates the location of the fire.
to-report fire-location-s
  report (list "fire" list pxcor pycor)
end

to-report fire-coords [fire-loc-rec]
  report item 1 fire-loc-rec
end

to-report x-fire-coord [fire-loc-rec]
  report first fire-coords fire-loc-rec
end

to-report y-fire-coord [fire-loc-rec]
  report item 1 fire-coords fire-loc-rec
end
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Sensors
;; Detecting obstacles in front of the unit.
;; Obstacles are fire and other ground units.
to-report detect-obstacle
foreach (list (patch-ahead 1)
    (patch-left-and-ahead 20 1)
    (patch-right-and-ahead 20 1)
         )
  [if any? fires-on ? [report true]
   if any? units-on ? and not (count units-on ? = 1 and one-of units-on ? = self) [report true]
  ]
report false
end

;;; The only obstacles for scouters are fires.
to-report detect-obstacle-scouter
foreach (list (patch-ahead 1)
      (patch-left-and-ahead 20 1)
      (patch-right-and-ahead 20 1)
         )
  [if any? fires-on ? [report true]]
report false
end


;;; detects a fire in the neighborhood of the unit (8 patches areound unit)
to-report detect-fire
  ifelse any? fires-on neighbors
    [report true]
    [report false]
end

;;; no fires around.
to-report fire-out
  ifelse any? fires-on neighbors
    [report false]
    [report true]
end

;;; reports that the unit is at the base (patch with color red)
to-report at-base
  ifelse [pcolor] of patch-here = red
    [report true]
    [report false]
end

;;;Use this to make sure that only one scout reports the same fire
;;; reports true if our agent is at the destination. Works equally well
;;; with agent IDs and x y Coordinates.
to-report at-dest [dest]
if is-number? dest [
 ifelse ([who] of one-of turtles-here = dest)
    [report true]
    [report false]
    ]

if is-list? dest [
 ifelse (abs (xcor - first dest) < 0.5 ) and (abs (ycor - item 1 dest) < 0.5)
    [report true]
    [report false]
    ]
end

;;; reports that the unit has water
to-report have-water
  ifelse water > 0
    [report true]
    [report false]
end

;;; reports (returns true) that the unit needs water supplies
to-report need-water
  ifelse water = 0
    [set color grey report true]
    [report false]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Actions of the agent
;;; Puts out a fire in the neighborhood. However since there can be multiple fires
;;; one of the eight possible fires is put out. In each operation it consumes one unit of water.
to put-out-fire
if detect-fire [
      ask one-of fires-on neighbors [extinguish]
      set water water - 1
      set saved-trees saved-trees + 1
      ]
end

;;;; Actions that move the agent around.
;;; Turning randomly to avod an obstacle
to avoid-obstacle
  set heading heading + random 360
end

;; moving towards the base by following the signal. First move and then turn
;; towards the base.
to move-towards-base
  move-ahead
  face min-one-of neighbors [signal]
end

;;; Moves towards a specific destination, but avoiding obstacles reactively.
to move-towards-dest [dest]
  if detect-obstacle [avoid-obstacle stop]
  if true [travel-towards dest stop]
end

to patrol
  if detect-obstacle [avoid-obstacle stop]
  if true [move-randomly]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Agent action that travels towards a destination. The destination can be either
;; a turtle ID or a set of coordinates in the form of a list.
to travel-towards [dest]
   move-ahead
   if is-number? dest
   [if not ((xcor = [xcor] of turtle dest) and (ycor = [ycor] of turtle dest))
     [set heading towards turtle dest] ];; safe towards

   if is-list? dest
   [if not ((xcor = first dest) and (ycor = item 1 dest))
     [set heading towardsxy (first dest) (item 1 dest)] ];; safe towards
end


;; moving randomly. First move then turn
to move-randomly
  move-ahead
  turn-randomly
end

;; Moves ahead the agent. Its speed is inversly proportional to the water it is carrying.
to move-ahead
  fd 1 - (water / (initial-water + 5))
end

;;; Turns the unit at a random direction
to turn-randomly
  set heading heading + random 30 - random 30
end

;;; service unit action is used for "recharging" the unit with water.
to service-unit
   set water initial-water
   set color blue
end

;;;; scouter specific
to scouter-random-move
  scouter-move
  set heading heading + random 35 - random 35
end

to scouter-move
  fd 0.5
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Utilities
to rand-xy-co
  let x 0
  let y 0

  loop [
    set x random-pxcor
    set y random-pycor
    if not any? turtles-on patch x y and not (abs x < 4 and abs y < 4) [setxy x y stop]
  ]
end

;;; Reporter that counts the number of trees (unaffected) left.
to-report trees-left
  report count trees
end
@#$#@#$#@
GRAPHICS-WINDOW
327
10
1015
506
25
17
13.3
1
10
1
1
1
0
1
1
1
-25
25
-17
17
1
1
1
ticks
30.0

BUTTON
96
10
160
43
Setup
setupSimulationEnvironment
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
167
10
230
43
run
run-experiment
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
236
10
314
43
run cont
run-experiment
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
149
68
321
101
initial-water
initial-water
0
50
25
1
1
NIL
HORIZONTAL

TEXTBOX
151
47
301
65
Unit Configuration
11
0.0
0

TEXTBOX
19
47
149
65
Environment Parameters
11
0.0
0

MONITOR
164
368
312
413
Number of Dead Trees
dead-trees
3
1
11

MONITOR
164
277
321
322
Number of Simulation Fires left
fires-left-in-sim
3
1
11

MONITOR
164
322
312
367
Number of Saved Trees
saved-trees
3
1
11

MONITOR
164
414
312
459
Number of Unaffected Trees
trees-left
3
1
11

TEXTBOX
167
254
317
272
Experiment Monitoring
11
0.0
0

TEXTBOX
48
19
92
37
Controls
11
0.0
0

CHOOSER
17
117
117
162
tree-num
tree-num
100 200 300 400 500
4

CHOOSER
17
70
116
115
fire-units-num
fire-units-num
1 5 10 20 30 40 50
4

CHOOSER
17
160
117
205
number-of-fires
number-of-fires
1 3 5 10 15 20 30 40
7

MONITOR
164
460
312
505
Units Destroyed
units-destroyed
3
1
11

CHOOSER
18
207
117
252
scouter-num
scouter-num
1 5 10 15 20 25 30
6

SWITCH
17
323
142
356
show_messages
show_messages
1
1
-1000

SWITCH
17
360
142
393
show-intentions
show-intentions
1
1
-1000

TEXTBOX
20
301
170
319
Debugging Facilities
11
0.0
1

@#$#@#$#@
## WHAT IS IT?

This section could give a general understanding of what the model is trying to show or explain.

## HOW IT WORKS

This section could explain what rules the agents use to create the overall behavior of the model.

## HOW TO USE IT

This section could explain how to use the model, including a description of each of the items in the interface tab.

## THINGS TO NOTICE

This section could give some ideas of things for the user to notice while running the model.

## THINGS TO TRY

This section could give some ideas of things for the user to try to do (move sliders, switches, etc.) with the model.

## EXTENDING THE MODEL

This section could give some ideas of things to add or change in the procedures tab to make the model more complicated, detailed, accurate, etc.

## NETLOGO FEATURES

This section could point out any especially interesting or unusual features of NetLogo that the model makes use of, particularly in the Procedures tab.  It might also point out places where workarounds were needed because of missing features.

## RELATED MODELS

This section could give the names of models in the NetLogo Models Library or elsewhere which are of related interest.

## CREDITS AND REFERENCES

This section could contain a reference to the model's URL on the web if it has one, as well as any other necessary credits or references.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

ant
true
0
Polygon -7500403 true true 136 61 129 46 144 30 119 45 124 60 114 82 97 37 132 10 93 36 111 84 127 105 172 105 189 84 208 35 171 11 202 35 204 37 186 82 177 60 180 44 159 32 170 44 165 60
Polygon -7500403 true true 150 95 135 103 139 117 125 149 137 180 135 196 150 204 166 195 161 180 174 150 158 116 164 102
Polygon -7500403 true true 149 186 128 197 114 232 134 270 149 282 166 270 185 232 171 195 149 186
Polygon -7500403 true true 225 66 230 107 159 122 161 127 234 111 236 106
Polygon -7500403 true true 78 58 99 116 139 123 137 128 95 119
Polygon -7500403 true true 48 103 90 147 129 147 130 151 86 151
Polygon -7500403 true true 65 224 92 171 134 160 135 164 95 175
Polygon -7500403 true true 235 222 210 170 163 162 161 166 208 174
Polygon -7500403 true true 249 107 211 147 168 147 168 150 213 150

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

bee
true
0
Polygon -1184463 true false 152 149 77 163 67 195 67 211 74 234 85 252 100 264 116 276 134 286 151 300 167 285 182 278 206 260 220 242 226 218 226 195 222 166
Polygon -16777216 true false 150 149 128 151 114 151 98 145 80 122 80 103 81 83 95 67 117 58 141 54 151 53 177 55 195 66 207 82 211 94 211 116 204 139 189 149 171 152
Polygon -7500403 true true 151 54 119 59 96 60 81 50 78 39 87 25 103 18 115 23 121 13 150 1 180 14 189 23 197 17 210 19 222 30 222 44 212 57 192 58
Polygon -16777216 true false 70 185 74 171 223 172 224 186
Polygon -16777216 true false 67 211 71 226 224 226 225 211 67 211
Polygon -16777216 true false 91 257 106 269 195 269 211 255
Line -1 false 144 100 70 87
Line -1 false 70 87 45 87
Line -1 false 45 86 26 97
Line -1 false 26 96 22 115
Line -1 false 22 115 25 130
Line -1 false 26 131 37 141
Line -1 false 37 141 55 144
Line -1 false 55 143 143 101
Line -1 false 141 100 227 138
Line -1 false 227 138 241 137
Line -1 false 241 137 249 129
Line -1 false 249 129 254 110
Line -1 false 253 108 248 97
Line -1 false 249 95 235 82
Line -1 false 235 82 144 100

bird1
false
0
Polygon -7500403 true true 2 6 2 39 270 298 297 298 299 271 187 160 279 75 276 22 100 67 31 0

bird2
false
0
Polygon -7500403 true true 2 4 33 4 298 270 298 298 272 298 155 184 117 289 61 295 61 105 0 43

boat1
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 158 33 230 157 182 150 169 151 157 156
Polygon -7500403 true true 149 55 88 143 103 139 111 136 117 139 126 145 130 147 139 147 146 146 149 55

boat2
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 157 54 175 79 174 96 185 102 178 112 194 124 196 131 190 139 192 146 211 151 216 154 157 154
Polygon -7500403 true true 150 74 146 91 139 99 143 114 141 123 137 126 131 129 132 139 142 136 126 142 119 147 148 147

boat3
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 158 37 172 45 188 59 202 79 217 109 220 130 218 147 204 156 158 156 161 142 170 123 170 102 169 88 165 62
Polygon -7500403 true true 149 66 142 78 139 96 141 111 146 139 148 147 110 147 113 131 118 106 126 71

box
true
0
Polygon -7500403 true true 45 255 255 255 255 45 45 45

bulldozer top
true
0
Rectangle -7500403 true true 195 60 255 255
Rectangle -16777216 false false 195 60 255 255
Rectangle -7500403 true true 45 60 105 255
Rectangle -16777216 false false 45 60 105 255
Line -16777216 false 45 75 255 75
Line -16777216 false 45 105 255 105
Line -16777216 false 45 60 255 60
Line -16777216 false 45 240 255 240
Line -16777216 false 45 225 255 225
Line -16777216 false 45 195 255 195
Line -16777216 false 45 150 255 150
Polygon -1184463 true true 90 60 75 90 75 240 120 255 180 255 225 240 225 90 210 60
Polygon -16777216 false false 225 90 210 60 211 246 225 240
Polygon -16777216 false false 75 90 90 60 89 246 75 240
Polygon -16777216 false false 89 247 116 254 183 255 211 246 211 211 90 210
Rectangle -16777216 false false 90 60 210 90
Rectangle -1184463 true true 180 30 195 90
Rectangle -16777216 false false 105 30 120 90
Rectangle -1184463 true true 105 45 120 90
Rectangle -16777216 false false 180 45 195 90
Polygon -16777216 true false 195 105 180 120 120 120 105 105
Polygon -16777216 true false 105 199 120 188 180 188 195 199
Polygon -16777216 true false 195 120 180 135 180 180 195 195
Polygon -16777216 true false 105 120 120 135 120 180 105 195
Line -1184463 true 105 165 195 165
Circle -16777216 true false 113 226 14
Polygon -1184463 true true 105 15 60 30 60 45 240 45 240 30 195 15
Polygon -16777216 false false 105 15 60 30 60 45 240 45 240 30 195 15

butterfly1
true
0
Polygon -16777216 true false 151 76 138 91 138 284 150 296 162 286 162 91
Polygon -7500403 true true 164 106 184 79 205 61 236 48 259 53 279 86 287 119 289 158 278 177 256 182 164 181
Polygon -7500403 true true 136 110 119 82 110 71 85 61 59 48 36 56 17 88 6 115 2 147 15 178 134 178
Polygon -7500403 true true 46 181 28 227 50 255 77 273 112 283 135 274 135 180
Polygon -7500403 true true 165 185 254 184 272 224 255 251 236 267 191 283 164 276
Line -7500403 true 167 47 159 82
Line -7500403 true 136 47 145 81
Circle -7500403 true true 165 45 8
Circle -7500403 true true 134 45 6
Circle -7500403 true true 133 44 7
Circle -7500403 true true 133 43 8

circle
false
0
Circle -7500403 true true 35 35 230

fire-unit
true
0
Rectangle -13840069 true false 60 30 240 270
Rectangle -955883 true false 60 240 120 270
Rectangle -955883 true false 60 195 120 225
Rectangle -955883 true false 60 150 120 180
Rectangle -955883 true false 60 105 120 135
Rectangle -955883 true false 60 60 120 90
Rectangle -955883 true false 60 30 120 45
Rectangle -955883 true false 180 240 240 270
Rectangle -955883 true false 180 195 240 225
Rectangle -955883 true false 180 150 240 180
Rectangle -955883 true false 180 105 240 135
Rectangle -955883 true false 180 60 240 90
Rectangle -955883 true false 180 30 240 45
Circle -2674135 true false 118 -2 62
Rectangle -7500403 true true 105 45 195 255

person
false
0
Circle -7500403 true true 155 20 63
Rectangle -7500403 true true 158 79 217 164
Polygon -7500403 true true 158 81 110 129 131 143 158 109 165 110
Polygon -7500403 true true 216 83 267 123 248 143 215 107
Polygon -7500403 true true 167 163 145 234 183 234 183 163
Polygon -7500403 true true 195 163 195 233 227 233 206 159

scouter
true
0
Rectangle -7500403 true true 90 15 210 285
Circle -2674135 true false 105 30 90
Rectangle -13345367 true false 120 150 180 255

sheep
false
15
Rectangle -1 true true 90 75 270 225
Circle -1 true true 15 75 150
Rectangle -16777216 true false 81 225 134 286
Rectangle -16777216 true false 180 225 238 285
Circle -16777216 true false 1 88 92

spacecraft
true
0
Polygon -7500403 true true 150 0 180 135 255 255 225 240 150 180 75 240 45 255 120 135

thin-arrow
true
0
Polygon -7500403 true true 150 0 0 150 120 150 120 293 180 293 180 150 300 150

tile stones
false
0
Polygon -7500403 true true 0 240 45 195 75 180 90 165 90 135 45 120 0 135
Polygon -7500403 true true 300 240 285 210 270 180 270 150 300 135 300 225
Polygon -7500403 true true 225 300 240 270 270 255 285 255 300 285 300 300
Polygon -7500403 true true 0 285 30 300 0 300
Polygon -7500403 true true 225 0 210 15 210 30 255 60 285 45 300 30 300 0
Polygon -7500403 true true 0 30 30 0 0 0
Polygon -7500403 true true 15 30 75 0 180 0 195 30 225 60 210 90 135 60 45 60
Polygon -7500403 true true 0 105 30 105 75 120 105 105 90 75 45 75 0 60
Polygon -7500403 true true 300 60 240 75 255 105 285 120 300 105
Polygon -7500403 true true 120 75 120 105 105 135 105 165 165 150 240 150 255 135 240 105 210 105 180 90 150 75
Polygon -7500403 true true 75 300 135 285 195 300
Polygon -7500403 true true 30 285 75 285 120 270 150 270 150 210 90 195 60 210 15 255
Polygon -7500403 true true 180 285 240 255 255 225 255 195 240 165 195 165 150 165 135 195 165 210 165 255

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

truck-down
false
0
Polygon -7500403 true true 225 30 225 270 120 270 105 210 60 180 45 30 105 60 105 30
Polygon -8630108 true false 195 75 195 120 240 120 240 75
Polygon -8630108 true false 195 225 195 180 240 180 240 225

truck-left
false
0
Polygon -7500403 true true 120 135 225 135 225 210 75 210 75 165 105 165
Polygon -8630108 true false 90 210 105 225 120 210
Polygon -8630108 true false 180 210 195 225 210 210

truck-right
false
0
Polygon -7500403 true true 180 135 75 135 75 210 225 210 225 165 195 165
Polygon -8630108 true false 210 210 195 225 180 210
Polygon -8630108 true false 120 210 105 225 90 210

turtle
true
0
Polygon -7500403 true true 138 75 162 75 165 105 225 105 225 142 195 135 195 187 225 195 225 225 195 217 195 202 105 202 105 217 75 225 75 195 105 187 105 135 75 142 75 105 135 105

wolf
false
0
Rectangle -7500403 true true 15 105 105 165
Rectangle -7500403 true true 45 90 105 105
Polygon -7500403 true true 60 90 83 44 104 90
Polygon -16777216 true false 67 90 82 59 97 89
Rectangle -1 true false 48 93 59 105
Rectangle -16777216 true false 51 96 55 101
Rectangle -16777216 true false 0 121 15 135
Rectangle -16777216 true false 15 136 60 151
Polygon -1 true false 15 136 23 149 31 136
Polygon -1 true false 30 151 37 136 43 151
Rectangle -7500403 true true 105 120 263 195
Rectangle -7500403 true true 108 195 259 201
Rectangle -7500403 true true 114 201 252 210
Rectangle -7500403 true true 120 210 243 214
Rectangle -7500403 true true 115 114 255 120
Rectangle -7500403 true true 128 108 248 114
Rectangle -7500403 true true 150 105 225 108
Rectangle -7500403 true true 132 214 155 270
Rectangle -7500403 true true 110 260 132 270
Rectangle -7500403 true true 210 214 232 270
Rectangle -7500403 true true 189 260 210 270
Line -7500403 true 263 127 281 155
Line -7500403 true 281 155 281 192

wolf-left
false
3
Polygon -6459832 true true 117 97 91 74 66 74 60 85 36 85 38 92 44 97 62 97 81 117 84 134 92 147 109 152 136 144 174 144 174 103 143 103 134 97
Polygon -6459832 true true 87 80 79 55 76 79
Polygon -6459832 true true 81 75 70 58 73 82
Polygon -6459832 true true 99 131 76 152 76 163 96 182 104 182 109 173 102 167 99 173 87 159 104 140
Polygon -6459832 true true 107 138 107 186 98 190 99 196 112 196 115 190
Polygon -6459832 true true 116 140 114 189 105 137
Rectangle -6459832 true true 109 150 114 192
Rectangle -6459832 true true 111 143 116 191
Polygon -6459832 true true 168 106 184 98 205 98 218 115 218 137 186 164 196 176 195 194 178 195 178 183 188 183 169 164 173 144
Polygon -6459832 true true 207 140 200 163 206 175 207 192 193 189 192 177 198 176 185 150
Polygon -6459832 true true 214 134 203 168 192 148
Polygon -6459832 true true 204 151 203 176 193 148
Polygon -6459832 true true 207 103 221 98 236 101 243 115 243 128 256 142 239 143 233 133 225 115 214 114

wolf-right
false
3
Polygon -6459832 true true 170 127 200 93 231 93 237 103 262 103 261 113 253 119 231 119 215 143 213 160 208 173 189 187 169 190 154 190 126 180 106 171 72 171 73 126 122 126 144 123 159 123
Polygon -6459832 true true 201 99 214 69 215 99
Polygon -6459832 true true 207 98 223 71 220 101
Polygon -6459832 true true 184 172 189 234 203 238 203 246 187 247 180 239 171 180
Polygon -6459832 true true 197 174 204 220 218 224 219 234 201 232 195 225 179 179
Polygon -6459832 true true 78 167 95 187 95 208 79 220 92 234 98 235 100 249 81 246 76 241 61 212 65 195 52 170 45 150 44 128 55 121 69 121 81 135
Polygon -6459832 true true 48 143 58 141
Polygon -6459832 true true 46 136 68 137
Polygon -6459832 true true 45 129 35 142 37 159 53 192 47 210 62 238 80 237
Line -16777216 false 74 237 59 213
Line -16777216 false 59 213 59 212
Line -16777216 false 58 211 67 192
Polygon -6459832 true true 38 138 66 149
Polygon -6459832 true true 46 128 33 120 21 118 11 123 3 138 5 160 13 178 9 192 0 199 20 196 25 179 24 161 25 148 45 140
Polygon -6459832 true true 67 122 96 126 63 144

@#$#@#$#@
NetLogo 5.3.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="show-intentions">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tree-num">
      <value value="300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-water">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fire-units-num">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="scouter-num">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show_messages">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-fires">
      <value value="40"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
