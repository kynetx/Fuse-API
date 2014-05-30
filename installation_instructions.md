
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

2. At the console prompt, enter the following command:

		CloudOS.getOAuthURL();

If you've correctly configure the console, clicking the URL that is returned should take you to an "Authorization" screen from the OAuth flow. The styling on this page is going to change.

Clicking on "Allow" will redirect you to the page you configure as the callback URL. You'll note that there is a parameter ```code``` in the redirect URL.  Copy the value of that parameter.

You can retrieve and access token and ECI by entering the following at the console (substituting the code you copied above for ```<code>```)

	CloudOS.getOAuthAccessToken("<code>", show_res)

You now type

    CloudOS.defaultECI

to see the ECI that was retrieved.  You can save the access_token/ECI object returned from ```getOAuthAccessToken()```  and restore it another session by doing the following

	CloudOS.saveSession(<eci>)

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
	                               "https://s3.amazonaws.com/k-mycloud/a169x672/7BD0B300-7DDF-11E2-AB3A-B9D7E71C24E1.img?q=97013",
								   "3GNFK16Z34G244122",
								   "C201300242",
								   show_res);

You should see a non-empty array of directives returned.

The VIN is required. The device ID is required if you want to initialize the vehicle in the Carvoyant account. The device ID can be supplied later. 

You should be able to ask the fleet for the vehicle channels:

	   Fuse.vehicleChannels(show_res)

2. You can delete a vehicle:
```Fuse.deleteVehicle(<vehicle_channel>, <callback>)``` takes the following parameters
	 - channel of vehicle to delete
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

You can use the following commands to see this data.

	Fuse.vehicleStatus()

	Fuse.vehicleSummary()

__Note:__ you won't see any data until the vehicle with the new device has been driven.


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

		Fuse.updateTrip: function(<vehicle_channel>, <trip_id>, <trip_name>, <trip_category>, <callback>)

The parameters are
	- vehicle channel
	- trip ID &mdash; 6-7 digit string
	- trip name &mdash; free form string naming the trip
	- trip category &mdash; free form string giving the trip category
	- callback

Note that the accepted categories for IRS purposes are "business," "medical," "moving," "charitable," and "other."

## Fuel

### Retrieving a Fillup

Fuel stored with the fill up time in UTC as the key


# Notes

1. This initial test uses direct login via user credentials. This will be allowed for mobile apps, but not from server-based cloud apps which will have to use OAuth.

2.  ```fuse:clean_up_subscriptions``` cleans up Carvoyant subscriptions, deleting any that don't point at the current vehicle pico.


# Debugging

_If you're unfamiliar with SquareTag and some of the activities you'll undertake as a developer, the [Quickstart](http://developer.kynetx.com/display/docs/Quickstart) has instructions about how to install rulesets, etc._

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

