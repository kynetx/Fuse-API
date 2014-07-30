
These are instructions for alpha stage users of the Fuse API.

Notes:

- For purposes of this document, a "Fuse app" is an app that a developer creates that uses OAuth to access the Fuse API.
- This document presumes a familiarity with OAuth.
- URLs and RIDs will change in these instructions as the API moves toward production
- Some of the operations in the following may be combined as I get more comfortable with what building blocks are really necessary in the API. 
- The API is under active development. Names, parameters, etc. are subject to change. What's more the API is running right now in a development environment and might be unavailable or broken at times. When this moves to beta, there will be a proper release to a production system and regular release procedures.

# Create an OAuth App in KDK

Notes:

- _If you're unfamiliar with SquareTag and some of the activities you'll undertake as a developer, the [Quickstart](http://developer.kynetx.com/display/docs/Quickstart) has instructions about how to install rulesets, etc._
- You only have to do this once for each Fuse app you create. 

Complete the following steps:

1.  Create an account at SquareTag.com if you don't have one. 
	 - An existing SquareTag account should be fine

1. Use the settings menu under your profile to set your Cloud Type to ```cloudTypeDeveloper```
    - Settings -> myCloud -> cloudTypeDeveloper

2. Install the Kynetx Developer Kit app
	- AppStore -> KDK
	- The SquareTag app store is a messy place when you're a developer. Sorry. 

3. Launch KDK and Create and App
    - Goto myApps
    - KDK -> Create an app
    - The fields are largely self-explanatory. The callback URL *must* be ```https```. Your users will be redirected here as part of the OAuth flow.
    - Save the app

1. Click on the app you just created in the KDK menu. There is an additional field (```bootstrap RID```)
    - Put ```b16x22.prod``` in this field and save
    - You will see a token called the App ECI listed at the bottom. You will need this as it is the identifier for your app.

# Install and Configure the JS API

1. Clone the Fuse-API Github repo to your development machine

2. Install and configure ```CloudOS-config.js``` from the template.
    - The App ECI from KDK is the ```appKey```.
	- The callbackURL is the same one you put in KDK.
	- For development, use ```kibdev.kobj.net``` as the host. 

3. Install and configure ```fuse-console-config.js``` from the template. 

When you load ```Fuse-console.html``` in a browser and open the console for the window.


# Provisioning Users

The following steps can be repeated for any new Fuse users. While you will be using the JavaScript console in your browser to complete these steps, they model the process your application will have to complete to provision a user.

- Create account
- Initialize account
- Authorize the Fuse account at Carvoyant

## Create a Fuse account for the user

Notes:

- Creating an account is, for now a separate step. It will be incorporated in the overall flow soon. 
- As a developer, you'll likely need a SquareTag account for managing your OAuth app registration. The Fuse account should be separate from the SquareTag account (i.e. different user name).
- Ensure you're logged out of SquareTag before creating a new user. Doing this in an incognito window in Chrome, or in a browser that is not logged into SquareTag will allow you to create multiple users and experiment with them and keep SquareTag open for debugging. 

Complete the following steps:

1. Go to the following URL and create an account. 

		https://cs.kobj.net/login/newaccount

2. At the JavaScript console prompt, enter the following command:

		CloudOS.getOAuthURL();

If you've correctly configure the console, clicking the URL that is returned should take you to an "Authorization" screen from the OAuth flow. The styling on this page is going to change.

Clicking on "Allow" will redirect you to the page you configure as the callback URL. You'll note that there is a parameter ```code``` in the redirect URL.  Copy the value of that parameter.

You can retrieve and access token and ECI by entering the following at the console (substituting the code you copied above for ```<code>```)

	CloudOS.getOAuthAccessToken("<code>", show_res)

You now type

    CloudOS.defaultECI

to see the ECI that was retrieved.  You can save the access_token/ECI object returned from ```getOAuthAccessToken()```. At the start of another session, you can restore it by doing the following

	CloudOS.saveSession({access_token: <access_token>, OAUTH_ECI: <oauth_eci>})

Note that CloudOS OAuth supports only the implicit flow. You will only get an access token, not a refresh token. 

## Initialize the New Account

The new account has a few bootstrap rulesets installed, but nothing else. We have to initialize it before it can be used.

*This step is likely to be automated in the final version of the API/SDK.*

You can type the following at the console to boostrap the account:

	Fuse.initAccount({"name": "Joe Driver", "email": "joe@driver.com", "phone": "8015551212", "photo": "<url>"}, show_res);

Note that all of the attributes are optional. ```show_res``` is the callback function. You can replace it with any callback function you like.

Note that this command is idempotent, so you can run it multiple times without ill effect. 


## Set up the Fleet Pico

Every Fuse users needs a fleet to manage their vehicles. A key part of initialization is setting up the fleet pico for the user.

Notes:

- The fleet is a singleton. You cannot have more than one fleet per Fuse user at present. That may change in the future. 


### Create a Fleet

 From the console prompt type

		Fuse.createFleet({}, show_res)

You should see something like this:

	Fuse: Creating fleet with attributes  Object {} fuse-api.js:75
	Attaching event parameters  Object {} CloudOS.js:47
	CloudOS.raise ESL:  https://kibdev.kobj.net/sky/event/86AC19AE-C7D0-11E3-9E9A-C4B987B7806A/6951351/fuse/need_fleet CloudOS.js:54
	event attributes:  Object {} CloudOS.js:55
	Object {readyState: 1, getResponseHeader: function, getAllResponseHeaders: function, setRequestHeader: function, overrideMimeType: function…}
	Fuse: Fleet created with channel  B8A64206-C7EC-11E3-891C-62D2E71C24E1 fuse-api.js:75
	Showing: Object {directives: Array[3]}

If you click into the directives object, you should see three directives:

	1. "requsting new Fuse setup"
	2. "Fleet created"
	3. "picoAttrSet"

While the number of directives might change over time, getting back an empty directive list (length === 0) means that creation failed

Note that you also have a fleet channel:

	Fuse.fleetChannel()

```Fuse.fleetChannel()``` will return the cached copy of the fleet ECI from the JavaScript unless you give it the ```force``` option which forces it to go to the API to reacquire the fleet channel. Note that the fleet channel is unlikely to change once a fleet has been created and is in use. 

Setting up the fleet is idempotent. That is, the code is written such that there will only ever by one fleet pico attached to a given owner.  Try running the ```fleetCreate()``` command again, you should get the same channel.

Creating a fleet creates a subscription to the fleet pico asynchronously. This means that the fleet channel isn't immidiately available for use. You should check ```Fuse.fleetChannel()``` to ensure it's not null before using it and wait if it's null. 

### Deleting a Fleet

You probably won't be deleting the fleet object very often, but it is available.

__Warning:__ Deleting the fleet also deletes all the vehicles. Don't delete the fleet unless you want to start completely over for a user.

The following command deletes the fleet pico:

		Fuse.deleteFleet(show_res)

You should see something like this:

	Attaching event parameters  Object {fleet_eci: "F57BF9CC-C7ED-11E3-921E-68D2E71C24E1"} CloudOS.js:47
	CloudOS.raise ESL:  https://kibdev.kobj.net/sky/event/86AC19AE-C7D0-11E3-9E9A-C4B987B7806A/422191/fuse/delete_fleet?fleet_eci=F57BF9CC-C7ED-11E3-921E-68D2E71C24E1 CloudOS.js:54
	event attributes:  Object {} CloudOS.js:55
	Object {readyState: 1, getResponseHeader: function, getAllResponseHeaders: function, setRequestHeader: function, overrideMimeType: function…}
	Fuse: Fleet deleted with ECI: F57BF9CC-C7ED-11E3-921E-68D2E71C24E1 fuse-api.js:75
	Showing: 
	Object {directives: Array[3]}

While the number of directives might change over time, getting back an empty directive list (length === 0) means that deletion failed

Now, ```Fuse.fleetChannel()``` will return ```null```.


## Authorize the Fuse account with Carvoyant

Fuse uses [Carvoyant](http://carvoyant.com) to provision devices, run the virtual mobile network that connects them, and run the backend servers for talking to the devices.  After much debate, we've determined that at this point Carvoyant needs to be known to users because they may have to authorize Fuse to work with Carvoyant from time to time (when tokens break). Consequently, users will have to take the extra step of creating a Carvoyant account.

*This step is subject to change. Specifically, it may be incorporated into other steps or go away altogether.*

1. Create an account at Carvoyant with the following command:

		Fuse.createCarvoyantAccount({"username": "<username>", "password":"<password>"}, show_res)

	This will create an account at Carvoyant with the username and password you provide using the profile elements from the fleet owner.

	Creating an account also creates initial Carvoyant credentials. These are stored in the fleet pico for later use in communicating with Carvoyant.

	The user is now provisioned and their Fuse Fleet is linked to Carvoyant.

	If the Carvoyant account was created correctly, you should be able to login to the [Carvoyant dashboard](https://dash.carvoyant.com) with the credentials you used to create the Carvoyant account.

Once the initial account creation is done, you can renew the tokens if necessary, but going through the Carvoyant OAuth flow. To assist in getting that right, there is a helper function that returns the Carvoyant OAuth URL:

	Fuse.carvoyantOauthUrl(<callback>)

This function will return a JSON object with the Carvoyant URL. Going to that URL in a browser will take the user to Carvoyant where they can log in with their Carvoyant credentials. Once they do that they will be redirected back to Fuse and the tokens will be returned and saved in the Fleet. You can distribute them to the vehicles with the following command:

	Fuse.configureVehicles({}, show_res)

(See configuring vehicles below.)

This command should be run whenever a new vehicle is added or the tokens have changed. 


# Adding a Vehicle

Now we can add some vehicles.

1. Add a vehicle with a name and photo
```createVehicle(<name>, <photo_url>, <vin>,  <deviceId>, <callback>)``` takes the following paramters:
      - name of vehicle
	  - URL of a profile photo for the vehicle
	  - Vehicle Identification Number
	  - Carvoyant device ID
	  - optional callback

	Here's an example:   

			Fuse.createVehicle("Lynne's Burb",
	                               "https://s3.amazonaws.com/k-mycloud...",
								   "3GNFK16Z34G244122",
								   "C201300242",
								   show_res);

	You should see a non-empty array of directives returned.

	The VIN is required. The device ID is required if you want to initialize the vehicle in the Carvoyant account. The device ID can be supplied later. 

	You should be able to ask the fleet for the vehicle channels:

			Fuse.vehicleChannels(show_res)

2. You can delete a vehicle:
```Fuse.deleteVehicle(<vehicle_id>, <callback>)``` takes the following parameters
	 - id of vehicle to delete (see ```Fuse.vehicleChannels``` to get an ID for existing vehicles)
	 - optional callback

# Configure the Vehicle

1. Update the carvoyant config for the vehicle.
```Fuse.configureVehicle({}, <callback>)``` takes the following parameters
	- empty attribute object
	- optional callback

	This tells the fleet pico to update all the vehicles with the latest Carvoyant tokens. This will usually happen automatically, but when you're creating a new vehicle, you have to do it manually to ensure it's done before you start making calls.

			Fuse.configureVehicles({}, show_res)
	
2. Initialize the Carvoyant Account for the vehicle
The following command creates the vehicle in the Carvoyant system with the device ID 

		Fuse.initCarvoyantVehicle(<vehicle_channel>, show_res);

You can provision as many vehicles in the account as you like.

# Initializing a Vehicle

You may have noticed that the update commands in the last section don't return data. If the API design succeeds, you will rarely need to call them and when you do, you will update the vehicle data pre-emptively, before it's needed.

For the most part, we rely on subscriptions to the vehicle itself to raise events into the Fuse system and thus automatically update critical vehicle information as events in the vehicle dictate.

When we initialize a vehicle, we set up four initial subscriptions:

- ```ignitionStatus``` &mdash; on or off
- ```lowBattery``` &mdash; below 12v
- ```troubleCode``` &mdash; any diagnostic trouble code
- ```fuelLevel```  &mdash; below 20%

We have taken care to ensure that these are idempotent so that the vehicle pico never sees multiple events for the same state change.

The ```ignitionStatus``` (when if goes to ```OFF```) causes the trip that just ended to be downloaded and made available in the vehicle and fleet picos. 

Initialize the vehicle:

	Fuse.initializeVehicle(<vehicle_channel>, <callback>, <options>);

takes the following parameters
	  - vehicle channel
	  - an optional callback function

It doesn't hurt to do this more than once, but you should avoid it if possible since it's an involved process with many API calls to Carvoyant.

Also, if you do it for multiple vehicle picos, Carvoyant will be raising events into each of those picos for the same car which puts a load on their system. There is a way, not exposed in the JavaScript yet, to clean up subscriptions and tell Carvoyant to delete all of them except for those pointing at the current pico (i.e. the pico talking to Carvoyant at the time). Automating this could lead to a dueling picos situation where multiple picos think they each represent the same car and steal subscriptions from Carvoyant from the others. Avoid this.

# Is It Right?

At this point, if you do the following:

	Fuse.vehicleSummary()

the return value should be an object with a property that is the device ID you used above that contains null values for it's sub properties:

	Object {C201200037: Object}
		C201200037: Object
			DTC: Object
			address: null
			fuellevel: null
			heading: null
			profileName: "Tacoma"
			profilePhoto: "https://s3.amazonaws.com/k-mycloud/a169x672/B87948E0-2306-11E3-953D-B39BDC00B96D.img?q=49420"
			speed: "0"

This is normal until you drive the vehicle.

You can also login to the [Carvoyant dashboard](https://dash.carvoyant.com) with the credentials you used to create the Carvoyant account. You should see any vehicles you've added there.

The following command should show you the subscriptions that Carvoyant has recorded for a vehicle:

	Fuse.vehicleSubscriptions(<vehicle_channel>, <callback>)

Normally, there should be four after the initialization above. 

# Use the SDK. 

If your configuration is connected to a real device in the Carvoyant system, you can tell Fuse to update the vehicle data from Carvoyant:
```Fuse.updateVehicleDataCarvoyant(<vehicle_channel>, <update_type>, <callback>, <options>);``` takes the following parameters
	  - vehicle channel
	  - the type of update (one of "summary", "status", or "trip")
	  - an optional callback function
	  - event attributes.


| Update Type | Attributes |
|-----------|---------|
| ```summary``` | none|
| ```status``` | none|
| ```trip``` | ```tripId```|

This command updates the vehicle status for a vehicle with channel "ABC"

	  Fuse.updateVehicleDataCarvoyant("ABC", "status", show_res);

This command updates the vehicle summary for a vehicle with channel "ABC"

	  Fuse.updateVehicleDataCarvoyant("ABC", "summary", show_res);

This command updates the trip for trip "271563" on the same vehicle

	Fuse.updateVehicleDataCarvoyant("ABC", "trip", show_res,{"tripId": "271563"});

Normally, there's no need to do this since the vehicles themselves force this update on ignition events. 

## Fleet Functions

There are several functions that provide fleet summary data. Each returns an array of objects. One of the properties in each object is ```picoId```. This is the system identifier of the vehicle in Fuse and will not change.

__Note:__ you won't see any data until the vehicle with the new device has been driven.

### Vehicle Channels

The following function returns an array of objects that associate a ```picoId``` with the current channel for that vehicle.

	Fuse.vehicleChannels(<callback>, <options>)

You should avoid using the channel as a means of identifying the vehicle since it could change. This function always provides the current mapping from the vehicle canonical name in the system, the ```picoId```, and the pico channel. 

### Vehicle Status

The following function returns an array of vehicle status information (i.e., lastest data elements from Carvoyant):

	Fuse.vehicleStatus(<callback>, <options>)

### Vehicle Summary

The following function returns an array of vehicle summary information for all the active vehicles in the system. 

	Fuse.vehicleSummary(<callback>, <options>)

The following properties are part of the objects that make up the array:

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

The trip summary contains the following elements for each vehicle:

- cost &mdash; total cost of all trips
- interval &mdash; total length of all trips in seconds
- mileage &mdash; total length of all trips in distance units (Fuse is unit agnostic)
- picoId &mdash; pico identifier
- trip_count &mdash; total number of trips for month

### Fuel Summaries

The following function takes a year and month and returns an array of  fuel summary objects  for that month:

	Fuse.fuelSummaries(<year>, <month>, <callback>, <options>)

The fuel summary contains the following elements for each vehicle:

- cost &mdash; total cost of all fillups in the given month
- distance &mdash; total distance driven between fillups
- fillups &mdash; number of fillups
- picoId &mdash; pico identifier
- volume &mdash; volume of fillups (e.g. gallons, liters, etc.)


## Trips

### Query Trips

The call to query trips is

	Fuse.trips(<vehicle_channel>,<start-time>,<end-time>, <callback>)

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

You can retrieve the last fillup or a specific fillup using the following function:

	Fuse.fillup(<vehicle_channel>, <callback>, <options>)

To retreive a specific fillup, you pass the key for the fillup as an option named ```key```.  Fillups are stored with the fill up time in UTC as the key.

If no key is provided, the function returns the most recent fillup.

You can also search fillups by date:

	Fuse.fillupByDate(<vehicle_channel>, <start>, <end>, <callback>, <options>)

where ```<start>``` and ```<end>``` are DateTime strings. 


### Recording a Fillup

You record a fillup using the following function:

	Fuse.recordFillup(<vehicle_channel>, <fillup_obj>, <callback>, <options>)

The fillup object has the following properties:
- ```volume``` &mdash; the volume of the fuel purchase.
- ```unitPrice``` &mdash; the price of a unit of fuel
- ```odometer``` &mdash; the odometer reading of the fuel purchase
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

# Notes

2.  ```fuse:clean_up_subscriptions``` cleans up Carvoyant subscriptions, deleting any that don't point at the current vehicle pico.



