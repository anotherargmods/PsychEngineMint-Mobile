package mobile.backend;

import haxe.ds.Map;
import haxe.Json;
import haxe.io.Path;
import openfl.utils.Assets;
import flixel.util.FlxSave;
import mobile.objects.TouchPad;

/**
 * Holds the virtual pad layouts loaded from `assets/shared/mobile` and the
 * mobile controls settings (mode, custom positions, extra buttons).
 * @author Karim Akra
 */
class MobileData
{
	public static var actionModes:Map<String, TouchButtonsData> = new Map();
	public static var dpadModes:Map<String, TouchButtonsData> = new Map();
	public static var extraActions:Map<String, ExtraActions> = new Map();

	public static var mode(get, set):Int;
	public static var forcedMode:Null<Int>;
	public static var save:FlxSave;

	/**
	 * Guards `init()`, the layouts and settings have to be read once per launch.
	*/
	public static var initialized:Bool = false;

	public static function init()
	{
		if (initialized)
			return;

		initialized = true;
		save = new FlxSave();
		save.bind('MobileControls', CoolUtil.getSavePath());

		readDirectory(Paths.getSharedPath('mobile/DPadModes'), dpadModes);
		readDirectory(Paths.getSharedPath('mobile/ActionModes'), actionModes);
		#if MODS_ALLOWED
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'mobile/'))
		{
			readDirectory(Path.join([folder, 'DPadModes']), dpadModes);
			readDirectory(Path.join([folder, 'ActionModes']), actionModes);
		}
		#end

		extraActions.set('SINGLE', ExtraActions.SINGLE);
		extraActions.set('DOUBLE', ExtraActions.DOUBLE);
		extraActions.set('NONE', ExtraActions.NONE);
	}

	public static function setTouchPadCustom(touchPad:TouchPad):Void
	{
		if (save.data.buttons == null)
		{
			save.data.buttons = new Array();
			for (buttons in touchPad)
				save.data.buttons.push(FlxPoint.get(buttons.x, buttons.y));
		}
		else
		{
			var tempCount:Int = 0;
			for (buttons in touchPad)
			{
				save.data.buttons[tempCount] = FlxPoint.get(buttons.x, buttons.y);
				tempCount++;
			}
		}

		save.flush();
	}

	public static function getTouchPadCustom(touchPad:TouchPad):TouchPad
	{
		var tempCount:Int = 0;

		if (save == null || save.data.buttons == null)
			return touchPad;

		for (buttons in touchPad)
		{
			if (save.data.buttons[tempCount] != null)
			{
				buttons.x = save.data.buttons[tempCount].x;
				buttons.y = save.data.buttons[tempCount].y;
			}
			tempCount++;
		}

		return touchPad;
	}

	public static function setButtonsColors(buttonsInstance:Dynamic):Dynamic
	{
		// Dynamic Controls Color
		var data:Dynamic = ClientPrefs.data;
		if (!ClientPrefs.data.dynamicColors)
		{
			var defaults:Dynamic = ClientPrefs.defaultData;
			if (defaults != null && defaults.arrowRGB != null)
				data = defaults;
		}

		var arrowRGB:Array<Array<FlxColor>> = data.arrowRGB != null ? data.arrowRGB : ClientPrefs.data.arrowRGB;

		buttonsInstance.buttonLeft.color = arrowRGB[0][0];
		buttonsInstance.buttonDown.color = arrowRGB[1][0];
		buttonsInstance.buttonUp.color = arrowRGB[2][0];
		buttonsInstance.buttonRight.color = arrowRGB[3][0];

		return buttonsInstance;
	}

	public static function readDirectory(folder:String, map:Dynamic)
	{
		folder = folder.contains(':') ? folder.split(':')[1] : folder;

		for (file in Paths.readDirectory(folder))
		{
			var fileWithNoLib:String = file.contains(':') ? file.split(':')[1] : file;
			if (Path.extension(fileWithNoLib) != 'json')
                        	continue;

			// `FileSystem.readDirectory` returns bare file names, so join them back to the folder
			var fullPath:String = fileWithNoLib.contains('/') ? fileWithNoLib : Path.join([folder, fileWithNoLib]);

			var str:String = null;

			#if MODS_ALLOWED
			if (FileSystem.exists(fullPath))
                        	str = File.getContent(fullPath);
			#end

			if (str == null && Assets.exists(fullPath))
                        	str = Assets.getText(fullPath);
			if (str == null && Assets.exists(fileWithNoLib))
                        	str = Assets.getText(fileWithNoLib);

			if (str == null)
				continue;

			var json:TouchButtonsData = cast Json.parse(str);
			var mapKey:String = Path.withoutDirectory(Path.withoutExtension(fileWithNoLib));
			map.set(mapKey, json);
		}
	}

	static function set_mode(mode:Int = 3)
	{
		save.data.mobileControlsMode = mode;
		save.flush();
		return mode;
	}

	static function get_mode():Int
	{
		if (forcedMode != null)
			return forcedMode;

		if (save == null)
			return 3;

		if (save.data.mobileControlsMode == null)
		{
			save.data.mobileControlsMode = 3;
			save.flush();
		}

		return save.data.mobileControlsMode;
	}
}

typedef TouchButtonsData =
{
	buttons:Array<ButtonsData>
}

typedef ButtonsData =
{
	button:String, // what TouchButton should be used, must be a valid TouchButton var from TouchPad as a string.
	graphic:String, // the graphic of the button, usually can be located in the TouchPad xml.
	x:Float, // the button's X position on screen.
	y:Float, // the button's Y position on screen.
	color:String // the button color, default color is white.
}

enum ExtraActions
{
	SINGLE;
	DOUBLE;
	NONE;
}
