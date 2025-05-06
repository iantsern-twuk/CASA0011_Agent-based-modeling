; Define global variables
globals [
  total-commute-time
  total-commuters
  avg-commute-time
  bike-usage-count
  public-transport-usage-count
  car-usage-count
  public-transport-density
  bike-available-rate
  total-bikes
]

; Define commuter agents
turtles-own [
  commute-mode   ; "bike", "public-transport", "car"
  start-patch    ; starting patch
  end-patch      ; destination patch
  start-time     ; commute start time
  end-time       ; arrival time
  trip-completed ; whether commute is completed
  waiting-ticks  ; waiting time at station
  my-transit-station ; the transit station the agent is waiting for
  has-bike       ; check if the agent has a bike
  max-wait-time  ; maximum waiting time tolerance
  current-wait-time ; current waiting time

]

; Define bike station
breed [bike-stations bike-station]
bike-stations-own [
  capacity       ; station capacity
  bikes-available ; available bikes count
]

; Define public transit stations
breed [public-transport-stations transit-station]
public-transport-stations-own [
  capacity       ; station capacity
  waiting-people ; people waiting at station
]

; Setup procedure
to setup
  clear-all
  resize-world -60 60 -60 60
  set-patch-size 5

  set total-commute-time 0
  set total-commuters 0
  set bike-usage-count 0
  set public-transport-usage-count 0
  set car-usage-count 0
  set simulate-multiple-trips true
  set public-transport-density 30

  create-stations
  create-population

  reset-ticks
  update-bike-station-size
end

; Set color based on commute mode
to set-commute-color
  if commute-mode = "bike" [ set color green ]
  if commute-mode = "public-transport" [ set color yellow ]
  if commute-mode = "car" [ set color red ]
end

; Decision-making: simplified version without distance
to decide-commute-mode
  ; set the od distance
  let od-distance distance end-patch
  let available-stations bike-stations with [bikes-available > 0]
  let nearest-bike-station nobody
  if any? available-stations [
    set nearest-bike-station min-one-of available-stations [distance myself]
  ]
  let nearest-transit-station min-one-of public-transport-stations [distance myself]

  ; set the distance to bike station and transit station
  let distance-to-bike-station 0
  if nearest-bike-station != nobody [
    set distance-to-bike-station distance nearest-bike-station
  ]
  let distance-to-transit-station 0
  if nearest-transit-station != nobody [
    set distance-to-transit-station distance nearest-transit-station
  ]

  ; set the utility parameters and calculate the utility of each mode
  let beta-cost 0.2
  let beta-time 0.2
  let beta-access 0.15

  let bike-utility exp(- beta-cost * bike-price -
                    beta-time * (od-distance / 15) * (1 + od-distance / 100) -
                    beta-access * distance-to-bike-station)

  let public-transport-utility exp(- beta-cost * 5 - beta-time * (od-distance / 20) -
                               beta-access * distance-to-transit-station -
                               0.2 * ([waiting-people] of nearest-transit-station / [capacity] of nearest-transit-station))
  let car-utility exp(- beta-cost * 10 -  ;
                    beta-time * (od-distance / 30) -
                    0.5 * (count turtles with [commute-mode = "car"] / population-size))

  ; check if the bike is available
  let can-use-bike false
  if nearest-bike-station != nobody and [bikes-available] of nearest-bike-station > 0 [
    set can-use-bike true
  ]

  ; compare the utility of other modes
  let max-utility max (list public-transport-utility car-utility)

  ; if the bike is available, compare it with other modes
  if can-use-bike [
    set max-utility max (list max-utility bike-utility)
  ]

  ; choose the mode based on the maximum utility
  let chosen-mode "car"
  let can-use-transit false

  ; check if the transit is available
  if [waiting-people] of nearest-transit-station < [capacity] of nearest-transit-station [
    set can-use-transit true
  ]

  ; choose the mode based on the maximum utility
  if max-utility = bike-utility [
    if can-use-bike and nearest-bike-station != nobody [
      ask nearest-bike-station [
        if bikes-available > 0 [
          set bikes-available bikes-available - 1
        ]
      ]
      ; only set has-bike when the bike is successfully borrowed
      if [bikes-available] of nearest-bike-station < [capacity] of nearest-bike-station [
        set has-bike 1
        set chosen-mode "bike"
      ]
    ]
  ]

  if max-utility = public-transport-utility [
    if can-use-transit [
      set chosen-mode "public-transport"
      set waiting-ticks max-wait-time
      set current-wait-time 0
      set my-transit-station nearest-transit-station
      ask nearest-transit-station [ set waiting-people waiting-people + 1 ]
    ]
  ]

  ; set the final chosen mode
  set commute-mode chosen-mode
end

; Return bike procedure
to return-bike
  let empty-stations bike-stations with [bikes-available < capacity]
  if any? empty-stations [
    let nearest-station min-one-of empty-stations [distance myself]
    if nearest-station != nobody [
      ask nearest-station [
        set bikes-available bikes-available + 1
      ]
      set has-bike 0
    ]
  ]
end

; Simulation running procedure
to go
  ; check if all agents are not moving
  if count turtles with [trip-completed = false] = 0 or
     (count turtles > 0 and count turtles = count turtles with [trip-completed = true]) [
    plot-pen-reset
    stop
  ]

  ; let the agents who need to decide the commute mode to decide
  ask turtles with [trip-completed = false] [
    if commute-mode = "bike" [
      let nearest-bike-station min-one-of bike-stations [distance myself]
      if nearest-bike-station != nobody and [bikes-available] of nearest-bike-station = 0 [
        if has-bike = 1 [
          return-bike
        ]
        decide-commute-mode
      ]
    ]
    if commute-mode = "public-transport" [
      if my-transit-station != nobody [
        set current-wait-time current-wait-time + 1
        if current-wait-time > max-wait-time [
          if [waiting-people] of my-transit-station >= [capacity] of my-transit-station [
            let other-stations public-transport-stations with [waiting-people < capacity]
            if any? other-stations [
              let new-station min-one-of other-stations [distance myself]
              if new-station != nobody [
                ask my-transit-station [ set waiting-people waiting-people - 1 ]
                set my-transit-station new-station
                ask new-station [ set waiting-people waiting-people + 1 ]
                set current-wait-time 0
              ]
            ]
            if not any? other-stations [
              ask my-transit-station [ set waiting-people waiting-people - 1 ]
              set my-transit-station nobody
              set current-wait-time 0
              decide-commute-mode
            ]
          ]
        ]
      ]
    ]
  ]

  ask turtles [
    if trip-completed = false [
      if commute-mode = "public-transport" and waiting-ticks > 0 [
        set waiting-ticks waiting-ticks - 1
        set current-wait-time current-wait-time + 1

        ; if the waiting time is longer than the max-wait-time, consider other options
        if current-wait-time > max-wait-time [
          let other-stations public-transport-stations with [waiting-people < capacity]
          if any? other-stations [
            let new-station min-one-of other-stations [distance myself]
            if new-station != nobody [
              ask my-transit-station [ set waiting-people waiting-people - 1 ]
              set my-transit-station new-station
              ask new-station [ set waiting-people waiting-people + 1 ]
              set current-wait-time 0
            ]
          ]
          if not any? other-stations [
            ask my-transit-station [ set waiting-people waiting-people - 1 ]
            set my-transit-station nobody
            set current-wait-time 0
            decide-commute-mode
          ]
        ]

        if waiting-ticks = 0 [
          if my-transit-station != nobody [
            ask my-transit-station [ set waiting-people waiting-people - 1 ]
          ]
        ]
        stop
      ]

      let speed get-movement-speed
      face end-patch
      fd speed
      handle-boundary-check

      if distance end-patch < 1 [
        move-to end-patch
        set end-time ticks
        set trip-completed true

        set total-commute-time total-commute-time + (end-time - start-time)
        set total-commuters total-commuters + 1

        ; only count the usage when the trip is completed
        if commute-mode = "bike" [ set bike-usage-count bike-usage-count + 1 ]
        if commute-mode = "public-transport" [ set public-transport-usage-count public-transport-usage-count + 1 ]
        if commute-mode = "car" [ set car-usage-count car-usage-count + 1 ]

        if commute-mode = "bike" and has-bike = 1 [
          return-bike
        ]

        if simulate-multiple-trips [
          set start-patch end-patch
          let start-x [pxcor] of start-patch
          let start-y [pycor] of start-patch
          set end-patch one-of patches with [pxcor != start-x or pycor != start-y]

          move-to start-patch
          set trip-completed false
          set commute-mode "none"
          if has-bike = 1 [
            return-bike
          ]
          decide-commute-mode
          set-commute-color
          set start-time ticks
        ]
      ]
    ]
  ]

  update-statistics
  update-bike-station-size
  update-transit-station-size
  tick
end

to update-bike-station-size
  ask bike-stations [
    ; set the size based
    set size 1 + 2 * (bikes-available / capacity)
  ]
end

to update-transit-station-size
  ask public-transport-stations [
    ; set the size based on the waiting-people/capacity, minimum 1, maximum 5
    set size 1 + 4 * (waiting-people / capacity)
    ; change the color based on the congestion
    if waiting-people > capacity * 0.8 [ set color red ]  ; show red if more than 80% capacity
    if waiting-people <= capacity * 0.8 [ set color orange ]  ; show orange if less than 80% capacity
  ]
end

; auxiliary function: check the bike availability
to-report check-bike-availability [station]
  report station != nobody and [bikes-available] of station > 0
end

; auxiliary function: check the transit station capacity
to-report check-transit-capacity [station]
  report station != nobody and [waiting-people] of station < [capacity] of station
end

; auxiliary function: calculate the movement speed
to-report get-movement-speed
  if commute-mode = "bike" [ report 0.3 ]
  if commute-mode = "public-transport" [ report 1 ]
  if commute-mode = "car" [ report 1 ]
  report 0
end

; auxiliary function: handle the boundary check
to handle-boundary-check
  if xcor > 60 [ set xcor -60 ]
  if xcor < -60 [ set xcor 60 ]
  if ycor > 60 [ set ycor -60 ]
  if ycor < -60 [ set ycor 60 ]
end

; auxiliary function: update the statistics
to update-statistics
  if total-commuters > 0 [
    set avg-commute-time total-commute-time / total-commuters
  ]
  set bike-available-rate (sum [bikes-available] of bike-stations) / total-bikes
end

; auxiliary function: create the stations
to create-stations
  ; Create bike stations
  create-bike-stations numbor-of-bike-stations [
    setxy random-xcor random-ycor
    set shape "circle"
    set color blue
    set capacity station-capacity
    set bikes-available random (capacity)
  ]
  set total-bikes sum [bikes-available] of bike-stations

  ; Create public transit stations
  create-public-transport-stations public-transport-density [
    setxy random-xcor random-ycor
    set shape "circle"
    set color orange
    set capacity 30
    set waiting-people 0
  ]
end

; auxiliary function: create the population
to create-population
  create-turtles population-size [
    set shape "person"
    set start-patch one-of patches
    set end-patch one-of patches
    move-to start-patch
    set trip-completed false
    set max-wait-time random 100 + 10
    set current-wait-time 0
    set waiting-ticks max-wait-time
    decide-commute-mode
    set has-bike ifelse-value (commute-mode = "bike") [1] [0]
    set start-time 0
    set-commute-color
  ]
end

; modify the plot calculation logic
to-report calculate-mode-percentage [mode-count]
  let total-count bike-usage-count + public-transport-usage-count + car-usage-count
  ifelse total-count > 0 [
    report (mode-count / total-count) * 100
  ] [
    report 0
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
823
624
-1
-1
5.0
1
10
1
1
1
0
1
1
1
-60
60
-60
60
0
0
1
ticks
30.0

SLIDER
10
12
202
45
numbor-of-bike-stations
numbor-of-bike-stations
10
200
100.0
1
1
NIL
HORIZONTAL

SLIDER
10
52
202
85
bike-price
bike-price
0
10
0.0
1
1
NIL
HORIZONTAL

SLIDER
10
91
202
124
station-capacity
station-capacity
2
10
10.0
1
1
NIL
HORIZONTAL

SLIDER
10
131
202
164
population-size
population-size
100
5000
1000.0
10
1
NIL
HORIZONTAL

BUTTON
12
214
104
247
Setup
setup
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
113
214
205
247
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
834
167
930
212
Bike (%)
(bike-usage-count / (bike-usage-count + public-transport-usage-count + car-usage-count)) * 100
1
1
11

MONITOR
1049
168
1171
213
public transport (%)
(public-transport-usage-count / (bike-usage-count + public-transport-usage-count + car-usage-count)) * 100
1
1
11

MONITOR
936
167
1044
212
car (%)
(car-usage-count / (bike-usage-count + public-transport-usage-count + car-usage-count)) * 100
1
1
11

MONITOR
1003
432
1171
477
Bike using rate (%)
(sum [has-bike] of turtles / total-bikes) * 100
1
1
11

PLOT
834
11
1173
161
Commute Mode Distribution
NIL
Count
0.0
5.0
0.0
100.0
true
true
"" ""
PENS
"Bike" 1.0 0 -10899396 true "" "plot calculate-mode-percentage bike-usage-count"
"public transport" 1.0 0 -1184463 true "" "plot calculate-mode-percentage public-transport-usage-count"
"Car" 1.0 0 -2674135 true "" "plot calculate-mode-percentage car-usage-count"

SWITCH
11
171
203
204
simulate-multiple-trips
simulate-multiple-trips
0
1
-1000

MONITOR
837
432
994
477
total bikes
total-bikes
17
1
11

MONITOR
836
381
993
426
Bikes-available
sum [bikes-available] of bike-stations
17
1
11

MONITOR
1001
380
1171
425
Bikes-using
sum [has-bike] of turtles
17
1
11

PLOT
835
221
1171
371
Bike using rate
NIL
NIL
0.0
10.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (sum [has-bike] of turtles / total-bikes) * 100"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
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
