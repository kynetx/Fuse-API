# Provisioning Users.

Most developers will not need this document. Rather, you should have your users use [Jounfuse.com](http://joinfuse.com/app.html) to

- create an account
- update their profile
- create and link a Carvoyant account
- add vehicles

If you want to use the functions described below to create a custom user provisioning system, you can. I recommend you carefully study the [provisioning code on Github](https://github.com/kynetx/Joinfuse) that implements the Joinfuse.com provisioning system.

If you want to create your own Fuse application that uses the Joinfuse.com provisioning system, but OAuths users to their account, they you will still need to 

- [Register your app with Kynetx for OAuth](#oauthapp)
- [Install and configure the JS SDKs for Fuse and CloudOS ](#fusejs)
- [Perform an OAuth interaction for your users](#oauthdance)


Notes:

- For purposes of this document, a "Fuse app" is an app that a developer creates that uses OAuth to access the Fuse API.
- This document presumes a familiarity with OAuth.
- URLs and RIDs will change in these instructions as the API moves toward production
- Some of the operations in the following may be combined as I get more comfortable with what building blocks are really necessary in the API. 
- The API is under active development. Names, parameters, etc. are subject to change. What's more the API is running right now in a development environment and might be unavailable or broken at times. When this moves to beta, there will be a proper release to a production system and regular release procedures.

# <a name="oauthapp"></a>Create an OAuth App in KDK

Notes:

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
    - Put ```b16x22.prod``` (or your own bootstrap RID) in this field and save
    - You will see a token called the App ECI listed at the bottom. You will need this as it is the identifier for your app.

# <a name="fusejs"></a>Install and Configure the JS API

1. Clone the Fuse-API Github repo to your development machine

2. Install and configure ```CloudOS-config.js``` from the template.
    - The App ECI from KDK is the ```appKey```.
	- The callbackURL is the same one you put in KDK.
	- For development, use ```kibdev.kobj.net``` as the host. 

3. Install and configure ```fuse-console-config.js``` from the template.

You can load ```Fuse-console.html``` in a browser and open the console for the window if you want to work at the command line to understand commands. 

In your app, you'll want to link to

- [current production version of CloudOS.js](https://s3.amazonaws.com/CloudOS_assets/js/CloudOS-1.0.0.js)
- [current production version of fuse-api.js](https://s3.amazonaws.com/Fuse_assets/js/fuse-api-1.0.0.js)


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

Go to the following URL and create an account. 

		https://cs.kobj.net/login/newaccount

## <a name="oauthdance"></a>OAuth  for the user

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

# Notes

2.  ```fuse:clean_up_subscriptions``` cleans up Carvoyant subscriptions, deleting any that don't point at the current vehicle pico.






https://github.com/kynetx/Fuse-API/blob/master/docs/Using_the_JavaScript_SDK.md
