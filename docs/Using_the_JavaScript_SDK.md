
# Fuse JavaScript SDK

This document describes the functions available in the Fuse JS SDK.

Note: the easiest way to use the SDK is to use [Joinfuse.com](http://joinfuse.com/app.html) to set up a user account, link it to a Carvoyant account, and add vehicles. Then you can use a JS console on that page to run the following commands. 

## Are You Connected

If everything is right, the following command should return a data value: 

	Fuse.vehicleSummary()

the return value should be an object with a property that is the device ID you used above that contains null values for it's sub properties:

	[
		Object
			DTC: Object
			address: null
			fuellevel: null
			heading: null
			profileName: "Tacoma"
			profilePhoto: "https://s3.amazonaws.com/k-mycloud/a169x672/B87948E0-2306-11E3-953D-B39BDC00B96D.img?q=49420"
			speed: "0"
		]

This is normal until you drive the vehicle.  


## Fleet Functions

There are several functions that provide fleet summary data. Each returns an array of objects. One of the properties in each object is ```picoId```. This is the system identifier of the vehicle in Fuse and will not change.

__Note:__ you won't see any data until the vehicle with the new device has been driven.

### Vehicle Channels

___Note: Your should treat all channels as a shared secret and not post them publicly.___ PicoIds are *not* sensitive and can be shared, posted, etc. 

The following function returns an array of objects that associate a ```picoId``` with the current channel for that vehicle.

	Fuse.vehicleChannels(<callback>, <options>)

You should avoid using the channel as a means of identifying the vehicle since it could change. This function always provides the current mapping from the vehicle canonical name in the system, the ```picoId```, and the pico channel.

___Callback___ The callback function will see an array of objects that have the following properties:

	channel: "720FD18D-215C-4F23-ABFD-06F62C2808F1"
	picoId: "Fleet-vehicle7010864A-215C-11E4-B874-136B8A2B85D9"


### Vehicle Status

The following function returns an array of vehicle status information (i.e., lastest data elements from Carvoyant):

	Fuse.vehicleStatus(<callback>, <options>)

___Callback___ The callback function will see an array of objects that have the following properties:

GEN_DTC &mdash;  Diagnostic Trouble Codes
GEN_VOLTAGE &mdash;  Battery Voltage
GEN_TRIP_MILEAGE &mdash;  Trip Mileage (calculate from ignition on to ignition off via GPS)
GEN_ODOMETER &mdash;  Vehicle Reported Odometer
GEN_WAYPOINT &mdash;  GPS Location
GEN_HEADING &mdash;  Heading (degrees clockwise from due north)
GEN_RPM &mdash;  Engine Speed
GEN_FUELLEVEL &mdash;  Percentage of Fuel Remaining
GEN_FUELRATE &mdash;  Rate of Fuel Consumption
GEN_ENGINE_COOLANT_TEMP &mdash;  Engine Temperature
GEN_SPEED &mdash;  Maximum Speed Recorded (since the previous reading)


### Vehicle Summary

The following function returns an array of vehicle summary information for all the active vehicles in the system. 

	Fuse.vehicleSummary(<callback>, <options>)

___Callback___ The callback function will see an array of objects that have the following properties:

- address &mdash; the latest human readable address where the vehicle is located
- channel &mdash; the channel that can be used to communicate with this vehicle
- deviceId &mdash; the Carvoyant device ID in the vehicle
- fuellevel &mdash; current fuel leve
- heading &mdash; current heading
- label &mdash; current label for the vehicle (usually the same as the name below)
- lastRunningTimestamp &mdash; the time the vehicle was last running
- lastWaypoint &mdash; the lastest LatLong coordinates for the vehicle
- mileage &mdash; current odometer reading
- name &mdash; make/model of vehicle based on VIN lookup
- picoId &mdash; the Fuse system identifier for the vehicle
- profileName &mdash; owners name for the vehicle
- profilePhoto &mdash; owners picture for the vehicle
- running &mdash; boolean indicating the current engine status
- speed &mdash; current speed 
- vehicleId &mdash; Carvoyant vehicle identifier
- vin &mdash; manufacturer's VIN; owner reported

### Trip Summaries

The following function takes a year and month and returns an array of  trip summary objects  for that month:

	Fuse.tripSummaries(<year>, <month>, <callback>, <options>)

```<year>``` and ```<month>``` are strings. Months must be two characters (i.e. ```"08"``` for August, not ```8```).

___Callback___ The callback function will see an array of objects that have the following properties:

- cost &mdash; total cost of all trips
- interval &mdash; total length of all trips in seconds
- mileage &mdash; total length of all trips in distance units (Fuse is unit agnostic)
- picoId &mdash; pico identifier
- trip_count &mdash; total number of trips for month


### Fuel Summaries

The following function takes a year and month and returns an array of  fuel summary objects  for that month:

	Fuse.fuelSummaries(<year>, <month>, <callback>, <options>)

```<year>``` and ```<month>``` are strings. Months must be two characters (i.e. ```"08"``` for August, not ```8```).

___Callback___ The callback function will see an array of objects that have the following properties:

- cost &mdash; total cost of all fillups in the given month
- distance &mdash; total distance driven between fillups
- fillups &mdash; number of fillups
- picoId &mdash; pico identifier
- volume &mdash; volume of fillups (e.g. gallons, liters, etc.)


## Trips

### Query Trips

#### Trip Lists
You can retrieve a list of trips or a specific trip using the following function:

	Fuse.trips(<vehicle_channel>, <id>, <limit>, <offset>, <callback>, <options>)

To retreive a specific trips, you pass the ID  of the trip as a parameter named ```id```.  If no ID is given, a paginated list of trips is returned. You can control the stating position of what is returned with ```offset``` and the number of items returned with ```limit```. By default these are 0 and 10 respectively.

Multiple trips are returned as trip summaries with the following structure:

- ```avgSpeed``` &mdash; Average speed for the trip
- ```cost``` &mdash; cost of trip (based on fuel records)
- ```endTime``` &mdash; DateTime string for end of trip (ignition off)
- ```endWaypoint``` &mdash; Waypoint object for end of trip
- ```id``` &mdash; trip identifier
- ```interval``` &mdash; length of trip in seconds
- ```mileage``` &mdash; length of trip in length units
- ```name``` &mdash; name of trip (if any)
- ```startTime``` &mdash;  DateTime string for start of trip (ignition on)
- ```startWaypoint``` &mdash; Waypoint object for end of trip

A single trip will show trip details:

- ```data``` &mdash; Array of vehicle-generated data and waypoints at multiple places along the trip
- ```endTime``` &mdash;  DateTime string for end of trip (ignition off)
- ```endWaypoint``` &mdash;  Waypoint object for end of trip
- ```id``` &mdash; trip identifier
- ```mileage``` &mdash; length of trip in length units
- ```startTime``` &mdash; DateTime string for start of trip (ignition on)
- ```startWaypoint``` &mdash; Waypoint object for end of trip

The data objects have the following properties:

- ```datum``` &mdash; Array of vehicle data (see Vehicle Status above for field descriptions)
- ```id``` &mdash; datum identifier
- ```ignitionStatus``` &mdash; vehicle on or off
- ```timestamp``` &mdash; time this data was generated. 

#### Trips by Date

You can get trips by date using the following function:

	Fuse.tripsByDate(<vehicle_channel>,<start-time>,<end-time>, <callback>)

The parameters are
	- vehicle channel
	- start time, an ISO8601 formatted datetime string such as "20140523T080000-0600"
	- end time, an ISO8601 formatted datetime string such as "20140523T150000-0600"
	- callback

Note that the trips are reported to Fuse and stored in Fuse with UTC datetime strings, but you can submit datetime strings with the local timezone. They will be normalized to UTC datetime strings before the query is processed.

### iCalendar Subscription

You can subscribe to trips using iCaledar. The API can generate the subscription URL for you with this call:

	Fuse.icalSubscriptionUrl(<vehicle_channel>,<callback>)

The parameters are
	- vehicle channel
	- callback

The iCalendar function only returns the last 25 trips.


### Updating a Trip

You can update a trip to change the meta data (trip name and category) with the following command:

		Fuse.updateTrip(<vehicle_channel>, <trip_id>, <trip_name>, <trip_category>, <callback>)

The parameters are
	- vehicle channel
	- trip ID &mdash; 6-7 digit string
	- trip name &mdash; free form string naming the trip
	- trip category &mdash; free form string giving the trip category
	- callback

Note that the accepted categories for IRS purposes are "business," "medical," "moving," "charitable," and "other."

## Fuel

### Retrieving a Fillup Record

You can retrieve fillups or a specific fillup using the following function:

	Fuse.fillups(<vehicle_channel>, <callback>, <options>)

To retreive a specific fillup, you pass the ID for the  as an option named ```id```.  If no ID is given, a paginated list of fillups is returned. You can control the stating position of what is returned with ```offset``` and the number of items returned with ```limit```. By default these are 0 and 10 respectively.

You can also search fillups by date:

	Fuse.fillupsByDate(<vehicle_channel>, <start>, <end>, <callback>, <options>)

where ```<start>``` and ```<end>``` are DateTime strings. 

A fillup record contains the following fields:

- cost &mdash; the total cost of the fillup
- distance &mdash; the distance between this fillup and the previous one
- interval &mdash; the length of time in seconds between this fillup and the previous one
- id &mdash; record identifier
- location &mdash; string giving location of fillup
- mpg &mdash; calculated distance/volume
- odometer &mdash; odometer reading at time of fillup
- timestamp &mdash; time of fillup
- unit_price &mdash; the price for a unit of fuel
- volume &mdash; the volume of fuel purchased


### Recording a Fillup

You record a fillup using the following function:

	Fuse.recordFillup(<vehicle_channel>, <fillup_obj>, <callback>, <options>)

The fillup object has the following properties:
- ```volume``` &mdash; the volume of the fuel purchase.
- ```unitPrice``` &mdash; the price of a unit of fuel
- ```odometer``` &mdash; the odometer reading of the fuel purchase; if missing, defaults to current odometer reading
- ```location``` &mdash; a string giving the location of the purchase
- ```when```&mdash;a DateTime string for the purchase; if missing, defaults to now. 

Note:

- The system is unitless, it's up to you to use consistent units.
- The fuel system relies on fuel purchases being entered in DateTime sequence to properly calculate MPG and distance traveled. New entries *do not* cause all entries with a later date to be updated. 

### Updating a Fillup Record

You update a fillup using the following function:

	Fuse.updateFillup(<vehicle_channel>, <fillup_obj>, <callback>, <options>)

In addition to the properties listed in the ```recordFillup()``` function above, you *must* supply a property called ```id``` that is the identifier of the fillup record you wish to update. 


### Deleting a Fillup Record

You delete a fillup using the following function:

	Fuse.deleteFillup(<vehicle_channel>, <id>, <callback>, <options>)

where ```id``` that is the key of the fillup record you wish to delete. 


## Maintenance

There are three different kinds of objects associated with maintenance.

- __Reminders__ &mdash; Reminders are the initial objects in a maintenance process. Reminders tell the owner that  scheduled maintenance is due. They can be one time or repeating and be mileage or time based.
- __Alerts__ &mdash; Alerts are the objects that tell an owner that something needs to be done. They can be created by a reminder that comes due, or some emergent activity in the vehicle such as a diagnostic code or low battery. Alerts can be active or inactive. When an alert is handled, it is made in active and a maintenance record is created. 
- __Maintenance Records__ &mdash; Maintenance records are usually created when an alert is handled, although they can be created directly as well.

### Reminders

Reminders represent a schedule of future maintenance activities. Reminders can occur ```once``` or be ```repeating```. 

#### Retrieving an Reminder

You can retrieve the a paginated list of reminders (most recent first) or a specific reminder using the following function:

	Fuse.reminders(<vehicle_channel>, <callback>, <options>)

To retreive a specific reminder, you pass the ID for the  as an option named ```id```.  If no ID is given, a paginated list of reminders is returned. You can control the stating position of what is returned with ```offset``` and the number of items returned with ```limit```. By default these are 0 and 10 respectively.

By default, ```reminders()``` returns only ```active``` reminders. You can pass an optional parameter called ```status``` to modify the conditions of the search. Valid values of ```status``` are ```active```, ```inactive```, or ```.*```. The latter retrieves all reminders regardless of status.

There is no way at present to retrieve reminders by date since that doesn't seem very useful.

You can, however, retrieve active reminders. An active reminder is one where either it's due date or due mileage has passed.

	Fuse.activeReminders(<vehicle_channel>, <date>, <mileage>, <callback>, <options>)

```<date>``` is a DateTime and mileage is an integer. 

```Fuse.activeRminders()``` is idempotent, so you can run it with future dates and mileage figures to see what items will become available. For example, running it with a date a week in the future and mileage 1000 miles from the current odometer reading would show any reminders that will come due in the next week or 1000 miles. 

#### Creating an Reminder

You create an reminder  using the following function:

	Fuse.recordReminder(<vehicle_channel>, <reminder_obj>, <callback>, <options>)

The reminder object has the following

- kind &mdash; one of ```date``` or ```mileage```
- recurring &mdash; one of ```once``` or ```repeat```
- interval &mdash; an integer specifying either a time in months or a mileage; ignored if ```recurring``` is ```once```.
- activity &mdash; a string stating the activity being reminded (e.g. "oil change")
- due &mdash; either a DateTime  for a date or an integer for an absolute odometer reading; ignored if ```recurring``` is ```repeat```.

If the value of ```recurring``` is ```repeat```, the due date or due mileage are calculated by adding the interval to the current date or odometer reading (depending on the value of ```kind```).

If the value of ```recurring``` is ```once```, the due date or due mileage are set to the value of ```due```  (depending on the value of ```kind```).


#### Updating a Reminder Record

You update an reminder using the following function:

	Fuse.updateReminder(<vehicle_channel>, <reminder_obj>, <callback>, <options>)

In addition to the properties listed in the ```recordReminder()``` function above, you *must* supply a property called ```id``` that is the id of the reminder record you wish to update. 


#### Deleting a Reminder Record

You delete an reminder using the following function:

	Fuse.deleteReminder(<vehicle_channel>, <id>, <callback>, <options>)

where ```id``` that is the key of the reminder record you wish to delete.

### Process Reminder

Reminders are processed automatically by the system on certain events. Thus, no SDK function exists for explicitly processing a reminder. 

### Alerts

#### Retrieving an Alert

You can retrieve the a paginated list of alerts (most recent first) or a specific alert using the following function:

	Fuse.alerts(<vehicle_channel>, <callback>, <options>)

To retreive a specific alert, you pass the ID for the  as an option named ```id```.  If no ID is given, a paginated list of alerts is returned. You can control the stating position of what is returned with ```offset``` and the number of items returned with ```limit```. By default these are 0 and 10 respectively.

By default, ```alerts()``` returns only ```active``` alerts. You can pass an optional parameter called ```status``` to modify the conditions of the search. Valid values of ```status``` are ```active```, ```inactive```, or ```.*```. The latter retrieves all alerts regardless of status.

You can also retrieve alerts by date:

	Fuse.alertsByDate(<vehicle_channel>, <start>, <end> <callback>, <options>)

The ```<start>``` and ```<end>``` parameters are DateTime objects.

 By default, only active alerts are returned.  As with ```alerts()``` you can pass an optional ```status``` parameter to change the status of the returned results.

#### Creating an Alert

You create an alert  using the following function:

	Fuse.recordAlert(<vehicle_channel>, <alert_obj>, <callback>, <options>)

The alert object has the following properties:

- activity &mdash;  activity being alerted (e.g. "Oil Change")
- odometer &mdash; odometer reading that the alert occured at; defaults to vehicle's current odomoeter reading. 
- reason &mdash; cause of  the alert (e.g. "5000 miles since previous oil change")
- reminder_ref &mdash; the ID of the reminder that created the alert (if any)
- status &mdash; status of alert; defaults to "active"
- when &mdash; time when alert is created; defaults to now
- trouble_codes &mdash; trouble codes that led to alert (if any)

Note:

- Activity and reason are free-form strings

#### Updating a Alert Record

You update an alert using the following function:

	Fuse.updateAlert(<vehicle_channel>, <alert_obj>, <callback>, <options>)

In addition to the properties listed in the ```recordAlert()``` function above, you *must* supply a property called ```id``` that is the id of the alert record you wish to update. 


#### Deleting a Alert Record

You delete an alert using the following function:

	Fuse.deleteAlert(<vehicle_channel>, <id>, <callback>, <options>)

where ```id``` that is the key of the alert record you wish to delete.

### Process Alert

Processing an alert makes the alert inactive and creates a new maintenance record that references it. The maintenance record will transfer information about activity, reason, and the generating reminder or trouble codes. 

You process an alert using the following function:

	Fuse.processAlert(<vehicle_channel>, <status_ob>, <callback>, <options>)

The status object has the following properties:

- id &mdash; the identifier for the alert to process
- status &mdash; the disposition of the alert. One of ```completed``` or ```deferred```
- agent &mdash; the person or organization who performed the maintenance
- receipt &mdash; the URL of the receipt or a ```data:image``` encoded picture of the receipt 

#### Alert Status

You can update the status of an alert with the following function:

	Fuse.updateAlertStatus(<vehicle_channel>, <id>, <new_status>, <callback>, <options>)

where ```id``` that is the key of the alert record you wish to update and ```new_status``` is the new status.

### Maintenance Records

#### Retrieving an Maintenance Record

You can retrieve the a paginated list of maintenance records (most recent first) or a specific maintenance record using the following function:

	Fuse.maintenanceRecords(<vehicle_channel>, <callback>, <options>)

To retreive a specific maintenance record, you pass the ID for the  as an option named ```id```.  If no ID is given, a paginated list of maintenance records is returned. You can control the stating position of what is returned with ```offset``` and the number of items returned with ```limit```. By default these are 0 and 10 respectively.

By default, ```maintenanceRecords()``` returns  all maintenance records. You can pass an optional parameter called ```status``` to modify the conditions of the search. Valid values of ```status``` are ```completed```, ```deferred```, or ```.*```. The latter retrieves all maintenance records regardless of status.

You can also retrieve maintenance records by date:

	Fuse.maintenanceRecordsByDate(<vehicle_channel>, <start>, <end> <callback>, <options>)

The ```<start>``` and ```<end>``` parameters are DateTime objects.

 By default, all maintenance records are returned.  As with ```maintenanceRecords()``` you can pass an optional ```status``` parameter to change the status of the returned results.

#### Creating an Maintenance Record

You create an maintenance record  using the following function:

	Fuse.recordMaintenanceRecord(<vehicle_channel>, <maintenance record_obj>, <callback>, <options>)

The maintenance record object has the following properties:


- status &mdash; the disposition of the alert. One of ```completed``` or ```deferred```; defaults to "unknown"
- agent &mdash; the person or organization who performed the maintenance
- cost &mdash; the cost of the maintenance item
- receipt &mdash; the URL of the receipt or a ```data:image``` encoded picture of the receipt 
- activity &mdash;  activity being maintenance recorded (e.g. "Oil Change")
- odometer &mdash; odometer reading that the maintenance record occured at; defaults to vehicle's current odomoeter reading. 
- reason &mdash; cause of  the maintenance record (e.g. "5000 miles since previous oil change")
- alert_ref &mdash; the ID of the alert that created the maintenance record (if any)
- reminder_ref &mdash; the ID of the reminder that created the alert that led to this maintenance record (if any)
- when &mdash; time when maintenance record is created; defaults to now

Note:

- Agent, activity, and reason are free-form strings
- If maintenance record is created from an alert, the activity and reason for the alert are transferred to the maintenance record by default. 

#### Updating a Maintenance Record Record

You update an maintenance record using the following function:

	Fuse.updateMaintenance Record(<vehicle_channel>, <maintenance record_obj>, <callback>, <options>)

In addition to the properties listed in the ```recordMaintenance Record()``` function above, you *must* supply a property called ```id``` that is the id of the maintenance record record you wish to update. 


#### Deleting a Maintenance Record Record

You delete an maintenance record using the following function:

	Fuse.deleteMaintenance Record(<vehicle_channel>, <id>, <callback>, <options>)

where ```id``` that is the key of the maintenance record record you wish to delete.

### Current Vehicle Status

The following returns the current status of a vehicle as most recently reported by the device (currently every 5 minutes while running).

	Fuse..currentVehicleStatus(<vehicle_channel>,  <callback>, <options>)

This function differs from the the fleet function ```vehicleStatus()``` because it returns the current status of a single vehicle (identified by the channel) rather that returning the cached vehicle status for each vehicle based on its last reported ignition event. 


