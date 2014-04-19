
These are instructions for alpha stage users of the Fuse API.

**These instructions are pre-release. The final released version of the API will likely be drastically different.  In addition, you're being required to complete a number of steps below (like installing certain rulesets, configuring Carvoyant, etc..) that will be automated for users. **



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

3. Install and configure ```fuse-api-test.js``` from the template. You'll need to set the ```username``` and ```password``` fields to the values you used when you created the SquareTag account above. 

When you load ```Fuse-console.html``` in a browser and open the console for the window. You should now type

    Fuse.user

at the console prompt and see the profile information for the owner profile. 

# Set up the Fleet Pico


Setting up the fleet is idempotent. That is, the code is written such that there will only ever by one fleet pico attached to a given owner. 

# Install One or More Vehicles


*run ```clean_up_subscriptions```*

Your now set up. Installing the vehicles set up notifications from your Fuse device so that it will raise events into the vehicle. These events will automatically update trips, vehicle info, vehicle status, and so on. 

# Notes

1. This initial test uses direct login via user credentials. This will be allowed for mobile apps, but not from server-based cloud apps which will have to use OAuth.


