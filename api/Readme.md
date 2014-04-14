

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
	    - ```fuel_level``` &mdash; most recent fuel level reading
		- ```timestamp``` &mdash; timestamp of reading
