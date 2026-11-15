This is addon for FFXI that manages trusts for you. You can create parties of your trusts, summon them, release them, release and resummon (to rescale their level). All in a nice looking package.
To be clear, this was entirely made with ChatGPT - if that bothers you then don't use it.

**GUI commands**

Command	Description

/tsets	Toggle the GUI open or closed

/trustsets	Same as /tsets

/tsets open	Open the GUI

/tsets close	Close the GUI

/tset gui	Toggle the GUI (legacy command)

 ------------------------------------------

**Trust preset management**

Command	Description

/tset list	List all saved Trust presets

/tset show NAME	Show the Trusts saved in a preset

/tset add NAME A, B, C	Create or update a preset with up to 5 Trusts

/tset capture NAME	Create a preset from your currently summoned Trusts

/tset capture	Capture current Trusts with an automatically generated preset name

/tset delete NAME	Delete a saved preset

 ------------------------------------------

**Summoning and party controls**

Command	Description

/tset run NAME	Summon the Trusts in a preset without dismissing existing Trusts

/tset replace NAME	Dismiss all current Trusts, then summon the selected preset

/tset release	Dismiss all currently summoned Trusts

/tset stop	Cancel the active summon queue, including retries

/tset status	Display current summoning progress and retry attempts

 ------------------------------------------

**Cast delay**

**Command	Description**

/tset delay	Display the current cast delay

/tset delay 4	Set delay to 4 seconds

/tset delay 5	Set delay to 5 seconds

/tset delay 6	Set delay to 6 seconds (default)

/tset delay 7	Set delay to 7 seconds

The delay is saved in your settings and is also adjustable from the GUI.

 ------------------------------------------

**Other commands**

Command	Description

/tset help	Display the addon's command help

/addon load trustsets	Load the addon

/addon reload trustsets	Reload the addon

/addon unload trustsets	Unload the addon

 ------------------------------------------

**Alternative command names**

The addon also recognizes several aliases:

- /tset summon NAME = /tset run NAME
- /tset switch NAME = /tset replace NAME
- /tset save NAME A, B, C = /tset add NAME A, B, C
- /tset current NAME = /tset capture NAME
- /tset remove NAME = /tset delete NAME
- /tset cancel = /tset stop
- /tset ui or /tset panel = /tset gui
