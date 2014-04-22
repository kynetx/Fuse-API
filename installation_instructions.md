
These are instructions for alpha stage users of the Fuse API.

_These instructions are pre-release. The final released version of the API will likely be drastically different.  In addition, you're being required to complete a number of steps below (like installing certain rulesets, configuring Carvoyant, etc..) that will be automated for users._


# Set up the Owner Pico

**If you're unfamiliar with SquareTag and some of the activities you'll undertake as a developer, the [Quickstart](http://developer.kynetx.com/display/docs/Quickstart) has instructions about how to install rulesets, etc. 

1. Create a Carvoyant account, if necessary and configure it:
	- create a vehicle
	- put the Carvoyant device ID in the vehicle profile
	-use the developer API to create a developer key and secret. Record these for later use. If you don't have access to the developer API, ask Caroyant for access.

1. Create a new account at SquareTag.com.
	- don't use an existing SquareTag account
	- use the new account to log into SquareTag (using an incognito window will allow you to continue to use SquareTag to support your development activities from your existing account.)
	- add a name and picture to the profile if you like.
	    - Settings -> Profile
	- use the settings menu under your profile to set your Cloud Type to ```cloudTypeDeveloper```
		- Settings -> myCloud -> cloudTypeDeveloper

1. Install the following rulesets with type Application:
	- Fuse: b16x16
	- Fuse Errors: b16x13
	- myApps -> Add devApp

1. You may want to install the PicoInspector for debugging

# Install and Configure the JS API

1. Clone the Fuse-API Github repo to your development machine

2. Install and configure ```CloudOS-config.js``` from the template.  You can ignore the appKey for now. 

3. Install and configure ```fuse-console-config.js``` from the template. You'll need to set the ```username``` and ```password``` fields to the values you used when you created the SquareTag account above.  You might also want to put test device configurations in this file to save having to type them over and over. 

When you load ```Fuse-console.html``` in a browser and open the console for the window. You should now type

    Fuse.user

at the console prompt and see the profile information for the owner profile you set up in SquareTag. 

# Set up the Fleet Pico

1. From the console prompt type

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

2. You can delete the fleet. 

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

# Install One or More Vehicles

Now we can add some vehicles.

1. Add a vehicle with a name and photo
```createVehicle(<name>, <photo_url>,<callback>)``` takes the following paramters:
      - name of vehicle
	  - URL of a profile photo for the vehicle
	  - optional callback

Here's an example:

		Fuse.addVehicle("Ford F-150", "https://s3.amazonaws.com/k-mycloud/a169x672/7BD0B300-7DDF-11E2-AB3A-B9D7E71C24E1.img?q=97013", show_res);

You should see a non-empty array of directives returned.

You should be able to ask the fleet for the vehicle channels:

	   Fuse.vehicleChannels(show_res)

2. You can delete a vehicle:
```Fuse.deleteVehicle(<vehicle_channel>, <callback>)``` takes the following parameters
	 - channel of vehicle to delete
	 - optional callback

# Configure the Vehicle

1. Install the Carvoyant keys and device ID
```Fuse.configureVehicle(<vehicle_channel>,<test_device_config>,<callback>)``` takes the following parameters
	 - vehicle channel to configure
	 - configuration values for device
	 - optional callback

For now, the configuration object looks like this:

	{"apiKey": "<carvoyant api key>",
	 "secToken": "<carvoyan security token>",
	 "deviceId": "<device id>"}

Now, let's see if the configuration is working. 

2. Test the configuration
If your configuration is connected to a real device in the Carvoyant system, you can tell Fuse to update the vehicle data from Carvoyant:
```Fuse.updateVehicleDataCarvoyant(<vehicle_id>, <update_type>, <callback>, <options>);``` takes the following parameters
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

You can use the following commands to see this data.

	Fuse.vehicleStatus()

	Fuse vehicleSummary()

*Trips are still incomplete waiting for searching*

# Initializing a Vehicle

You may have noticed that the update commands in the last section don't return data. If the API design succeeds, you will rarely need to call them and when you do, you will update the vehicle data pre-emptively, before it's needed.

For the most part, we rely on subscriptions to the vehicle itself to raise events into the Fuse system and thus automatically update critical vehicle information as events in the vehicle dictate.

When we initialize a vehicle, we set up four initial subscriptions:

- ```ignitionStatus``` &mdash; on or off
- ```lowBattery``` &mdash; below 12v
- ```troubleCode``` &mdash; any diagnostic trouble code
- ```fuelLevel```  &mdash; below 20%

We have taken care to ensure that these are idempotent so that the vehicle pico never sees multiple events for the same state change.

Initialize the vehicle:
```Fuse.updateVehicleDataCarvoyant(<vehicle_id>, <callback>, <options>);``` takes the following parameters
	  - vehicle channel
	  - an optional callback function

It doesn't hurt to do this more than once, but you should avoid it if possible since it's an involved process with many API calls to Carvoyant.

Also, if you do it for multiple vehicle picos, Carvoyant will be raising events into each of those picos for the same car which puts a load on their system. There is a way, not exposed in the JavaScript yet, to clean up subscriptions and tell Carvoyant to delete all of them except for those pointing at the current pico (i.e. the pico talking to Carvoyant at the time). Automating this could lead to a dueling picos situation where multiple picos think they each represent the same car and steal subscriptions from Carvoyant from the others. Avoid this. 

# Notes

1. This initial test uses direct login via user credentials. This will be allowed for mobile apps, but not from server-based cloud apps which will have to use OAuth.

2.  ```fuse:clean_up_subscriptions``` cleans up Carvoyant subscriptions, deleting any that don't point at the current vehicle pico.


