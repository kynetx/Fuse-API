

# Owner

## Events

- ```fuse:initialize``` &mdash; creates a fleet pico and a subscription (```Fleet-FleetOwner```)
    - sent to owner pico
	- no attributes
	- supposed to be idempotent (only one fleet pico gets created, a singleton)

- ```fuse:show_children``` &mdash;
    - sent to owner pico
    - shows child picos in directive

- ```fuse:delete_fleet``` &mdash;
    - send to owner pico
	- attributes
	    - fleet_eci: ECI of fleet to delete
    - improvement: since the fleet is a singleton, technically the ECI is unnecessary, we should be able to look it up

# Fleet

## Events

- ```fuse:need_new_vehicle``` &mdash; create a new vehicle pico and a subscription (```Vehicle-Fleet```)
    - sent to fleet pico
	- attributes:
	     - ```name```: textual name (nickname) of new vehicle. Random name chosen if none given.
		 - ```photo```: URL of photo of vehicle
		 
- ```fuse:show_vehicles``` &mdash; show the vehicles that are in the fleet
    - sent to fleet pico
    - shows vehicle picos in directive
	
- ```fuse:delete_vehicle``` &mdash; delete vehicle and its subscriptions
    - send to fleet pico
	- attributes
	    - ```vehicle_eci```: ECI of vehicle to delete

# Vehicle

## PDS

Vehicle's PDS (cavoyant namespace)

In general, use Carvoyant CamelCase identifiers in vehicle PDS for sanity

- ```config```
    - ```deviceId``` &mdash; Carvoyant device ID
    - ```apiKey``` &mdash; Carvoyant API Key
	- ```secToken``` &mdash; Carvoyant Secret Token

- ```vehicle_info```
    - ```vehicleId``` &mdash; carvoyant vehicle identifier

__A Note About Waypoints__: Carvoyant uses two formats for waypoints, a map with the keys ```latitude``` and ```longitude``` along with a timestamp and a comma separated string with latitude preceding longitude (latlong). Functions and rules have been designed to work with either without prejudice. 

## Functions

- ```vehicle:vin()``` &mdash; return vehicle reported VIN
- ```vehicle:vehicleInfo()``` &mdash; return all vehicle info including name, vin, last reported mileage, owner nickname, current location, and current ignition status
- ```vehicle:vehicleStatus(<key>)``` &mdash; return last reported operating status for 10 key values. ```<key>``` can be one of:
    - ```GEN_DTC``` &mdash;  Diagnostic Trouble Codes
	- ```GEN_VOLTAGE``` &mdash;  Battery Voltage
	- ```GEN_TRIP_MILEAGE``` &mdash;  Trip Mileage (last trip)
	- ```GEN_ODOMETER``` &mdash;  Vehicle Reported Odometer
	- ```GEN_WAYPOINT``` &mdash;  GPS Location
	- ```GEN_HEADING``` &mdash;  Heading
	- ```GEN_RPM``` &mdash;  Engine Speed
	- ```GEN_FUELLEVEL``` &mdash;  % Fuel Remaining
	- ```GEN_FUELRATE``` &mdash;  Rate of Fuel Consumption
	- ```GEN_ENGINE_COOLANT_TEMP``` &mdash;  Engine Coolant Temperature
	- ```GEN_SPEED``` &mdash;  Maximum Speed Recorded (last trip)


- ```trips:lastTrip(<with_data>)``` &mdash; return last trip information
    - ```startWaypoint``` &mdash; latitude, longitude, and timestamp
	- ```endWaypoint``` &mdash; latitude, longitude, and timestamp
    - ```endTime``` &mdash; time the trip ends
	- ```startTime``` &mdash; time the trip starts
    - ```id``` &mdash; unique trip identifier
    - ```data``` &mdash; array of detailed trip data, only returned if ```with_data``` is ```true```
- ```trips:tripName(<start>, <end>)``` &mdash; return tripId and tripName for the <start> and <end> waypoints.


## Events

- ```carvoyant:dirty_subscriptions``` &mdash; signals the possible presence of subscriptions in the carvoyant account that don't point at the current pico
    - ```clean_up_subscriptions``` &mdash; rule deletes any subscriptions in account that don't match current pico's carvoyant channel
	- Note that two picos connected to the same Carvoyant account would battle to get subscriptions created and delete the other's. I don't know how realistic this possibility is. 
- ```fuse:updated_mileage```&mdash; raised whenever there is a new mileage figure.  Rules interested in mileage should listen for this event.
    - attributes:
	    - ```mileage``` &mdash; most recent odometer reading
		- ```timestamp``` &mdash; timestamp of reading
- ```fuse:updated_fuellevel```&mdash; raised whenever there is a new fuel level figure.  Rules interested in fuel level should listen for this event. Not fired if fuel level is 0 since this most often indicates no reading. 
    - attributes:
	    - ```threshold``` &mdash; set threshold (note this is always 12V for now)
		- ```recorded``` &mdash; recorded value should be below threshold, but check since vehicle sometimes mistakenly reports
		- ```timestamp``` &mdash; timestamp of reading
- ```fuse:updated_battery``` &mdash; raised when vehicle reports battery level below set threshold.
    - attributes:
	    - ```threshold``` &mdash; set threshold (note this is always 12V for now)
		- ```recorded``` &mdash; recorded value should be below threshold, but check since vehicle sometimes mistakenly reports
		- ```timestamp``` &mdash; timestamp of reading
- ```fuse:updated_dtc``` &mdash; raised when vehicle reports diagnostic trouble codes'
    - attributes:
	    - ```codes``` &mdash; array of reported codes
		- ```timestamp``` &mdash; timestamp of reading
- ```fuse:new_trip``` &mdash; raised when there a new trip
    - attributes:
	    - ```tripId``` &mdash; the Carvoyant ID for the trip
		- Optionally, all of the values of the trip, in the Cavoyant format, can be send as individual event attributes and they'll be recorded without asking Carvoyant for the trip
- ```fuse:name_trip``` &mdash; a name is available for trip
    - attributes:
	    - ```tripId``` &mdash; the Carvoyant ID for the trip
	    - ```tripName``` &mdash; The string that names this trip
