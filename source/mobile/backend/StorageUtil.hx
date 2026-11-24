package mobile.backend;

import lime.system.System as LimeSystem;
import openfl.utils.Assets as OpenFlAssets;
import haxe.io.Path;
import haxe.Exception;

/**
 * Storage helpers for mobile platforms.
 * @author Mihai Alexandru (M.A. Jigsaw), Karim Akra and Lily Ross (mcagabe19)
 */
class StorageUtil
{
	#if sys
	/**
         * Root directory, used for handling the saved storage type and path.
	*/
	public static final rootDir:String = LimeSystem.applicationStorageDirectory;

	/**
	 * Folders the engine expects to find/write inside the game directory.
	*/
	public static final gameFolders:Array<String> = ['assets', 'mods', 'saves', 'crash', 'logs', 'backups'];

	/**
	 * Records the app version that populated the data folder, so updates can refresh it.
	*/
	static inline final extractionMarker:String = '.assets_extracted';

	/**
	 * Media is not copied out of the APK: images, audio and video are read straight
	 * from the package through `openfl.utils.Assets`, which is what `Paths` does when
	 * the file is not on the device. Copying them would only duplicate several
	 * hundred MB of read only data on first launch.
	*/
	static final skippedExtensions:Array<String> = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ogg', 'mp3', 'wav', 'mp4', 'webm'];

	public static function getStorageDirectory(?force:Bool = false):String
	{
		var daPath:String = '';
		#if android
		if (!FileSystem.exists(rootDir + 'storagetype.txt'))
			File.saveContent(rootDir + 'storagetype.txt', ClientPrefs.data == null ? StorageType.DEFAULT : ClientPrefs.data.storageType);
		var curStorageType:String = File.getContent(rootDir + 'storagetype.txt');
		daPath = force ? StorageType.fromStrForce(curStorageType) : StorageType.fromStr(curStorageType);
		#elseif ios
		daPath = LimeSystem.documentsDirectory;
		#else
		daPath = rootDir;
		#end

		return Path.addTrailingSlash(daPath);
	}

	public static function createDirectories(directory:String):Void
	{
		try
		{
			if (FileSystem.exists(directory) && FileSystem.isDirectory(directory))
				return;
		}
		catch (e:Exception)
		{
			trace('Something went wrong while looking at directory. (${e.message})');
		}

		var total:String = '';
		if (directory.substr(0, 1) == '/')
			total = '/';

		var parts:Array<String> = directory.split('/');
		if (parts.length > 0 && parts[0].indexOf(':') > -1)
			parts.shift();

		for (part in parts)
		{
			if (part != '.' && part != '')
			{
				if (total != '' && total != '/')
					total += '/';

				total += part;

				try
				{
					if (!FileSystem.exists(total))
						FileSystem.createDirectory(total);
				}
				catch (e:Exception)
					trace('Error while creating directory. (${e.message})');
			}
		}
	}

	public static function saveContent(fileName:String, fileData:String, ?alert:Bool = true):Void
	{
		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');

			File.saveContent('saves/$fileName', fileData);
			if (alert)
				CoolUtil.showPopUp('$fileName has been saved.', "Success!");
		}
		catch (e:Exception)
			if (alert)
				CoolUtil.showPopUp('$fileName couldn\'t be saved.\n(${e.message})', "Error!")
			else
				trace('$fileName couldn\'t be saved. (${e.message})');
	}

	public static function checkExternalPaths(?splitStorage = false):Array<String>
	{
		var paths:Array<String> = [];
		try
		{
			for (path in FileSystem.readDirectory('/storage'))
			{
				if (path == 'emulated' || path == 'self')
					continue;
				paths.push(splitStorage ? path : '/storage/$path');
			}
		}
		catch (e:Exception)
			trace('Could not read the external storage paths. (${e.message})');

		return paths;
	}

	public static function getExternalDirectory(externalDir:String):String
	{
		var daPath:String = '';
		for (path in checkExternalPaths())
			if (path.contains(externalDir))
				daPath = path;

		daPath = Path.addTrailingSlash(daPath.endsWith("\n") ? daPath.substr(0, daPath.length - 1) : daPath);
		return daPath;
	}

	/**
	 * Checks whether `directory` can be written to. Used to fall back to the app data
	 * folder when the external one is not accessible (missing MANAGE_EXTERNAL_STORAGE).
	 */
	public static function isWritable(directory:String):Bool
	{
		final probe:String = Path.addTrailingSlash(directory) + '.write_test';
		try
		{
			File.saveContent(probe, '');
			FileSystem.deleteFile(probe);
			return true;
		}
		catch (e:Exception)
		{
			trace('"$directory" is not writable. (${e.message})');
			return false;
		}
	}

	/**
	 * Creates the game directory and every sub folder the engine uses. Nothing is deleted,
	 * so an update never throws away mods, saves or crash logs.
	 * @return false when the directory could not be written to.
	 */
	public static function prepareGameDirectory(directory:String):Bool
	{
		final dir:String = Path.addTrailingSlash(directory);
		createDirectories(dir);

		if (!isWritable(dir))
			return false;

		for (folder in gameFolders)
			createDirectories(dir + folder);

		return true;
	}

	/**
	 * Copies the assets bundled inside the APK into `directory`, so `FileSystem` lookups
	 * (`Paths.getTextFromFile`, `Sound.fromFile`, mods...) behave like on desktop.
	 *
	 * Files already on disk are kept untouched unless the app version changed, which is how
	 * data coming from an older build gets refreshed without touching `mods/` or `saves/`.
	 * @return amount of files written, or -1 when the packaged asset list is unavailable.
	 */
	public static function extractBundledAssets(directory:String):Int
	{
		final dir:String = Path.addTrailingSlash(directory);
		final version:String = getAppVersion();
		final marker:String = dir + extractionMarker;

		var upToDate:Bool = false;
		try
		{
			upToDate = FileSystem.exists(marker) && StringTools.trim(File.getContent(marker)) == version;
		}
		catch (e:Exception)
		{
			trace('Could not read "$marker". (${e.message})');
		}

		if (upToDate)
			return 0;

		final ids:Array<String> = OpenFlAssets.list();
		if (ids == null || ids.length == 0)
		{
			// Writing the marker here would stop every future launch from trying again.
			trace('No packaged assets were listed, skipping asset extraction.');
			return -1;
		}

		var copied:Int = 0;
		var failed:Int = 0;
		for (id in ids)
		{
			if (!id.startsWith('assets/') || shouldSkipAsset(id))
				continue;

			try
			{
				final target:String = dir + id;
				createDirectories(Path.directory(target));

				final bytes = OpenFlAssets.getBytes(id);
				if (bytes == null || bytes.length == 0)
				{
					trace('Packaged asset "$id" is empty, skipping it.');
					failed++;
					continue;
				}

				File.saveBytes(target, bytes);
				copied++;
			}
			catch (e:Exception)
			{
				trace('Could not extract "$id". (${e.message})');
				failed++;
			}
		}

		trace('Extracted $copied asset(s) to "$dir" (failed: $failed).');

		if (failed > 0)
			return copied;

		try
		{
			File.saveContent(marker, version);
		}
		catch (e:Exception)
		{
			trace('Could not write "$marker". (${e.message})');
		}

		return copied;
	}

	/**
	 * Makes sure the bundled data really landed on the device.
	 */
	public static function verifyGameDirectory(directory:String):Bool
	{
		final dir:String = Path.addTrailingSlash(directory);
		final required:Array<String> = ['assets/shared/weeks/weekList.txt', 'assets/shared/data/characterList.txt'];
		#if BASE_GAME_FILES
		// weeks and charts of this build live in `assets/base_game`
		required.push('assets/shared/weeks/tutorial.json');
		#end

		var ok:Bool = true;
		for (file in required)
		{
			if (!FileSystem.exists(dir + file))
			{
				trace('Missing game file after extraction: "$dir$file"');
				ok = false;
			}
		}
		return ok;
	}

	/**
	 * Prepares the game directory, then restores anything bundled in the APK that is not there yet.
	 */
	public static function setupGameDirectory(directory:String):Bool
	{
		if (!prepareGameDirectory(directory))
		{
			trace('"$directory" is not writable, packaged assets will be read from the APK.');
			return false;
		}

		extractBundledAssets(directory);
		return verifyGameDirectory(directory);
	}

	static function shouldSkipAsset(id:String):Bool
	{
		final ext:String = Path.extension(id).toLowerCase();
		return skippedExtensions.contains(ext);
	}

	static function getAppVersion():String
	{
		final version:String = lime.app.Application.current.meta.get('version');
		return version == null ? '0' : version;
	}

	/**
	 * Copies `from` into `to`, recursively. When `only` is set, only those entries are copied.
	 * @return false when at least one entry could not be copied.
	 */
	public static function copyContents(from:String, to:String, ?only:Array<String>):Bool
	{
		from = Path.addTrailingSlash(from);
		to = Path.addTrailingSlash(to);

		if (!FileSystem.exists(from) || !FileSystem.isDirectory(from))
			return false;

		var ok:Bool = true;
		final names:Array<String> = only ?? FileSystem.readDirectory(from);
		for (name in names)
		{
			final src:String = from + name;
			final dst:String = to + name;
			try
			{
				if (!FileSystem.exists(src))
					continue;

				if (FileSystem.isDirectory(src))
					ok = copyDirectory(src, dst) && ok;
				else
					File.copy(src, dst);
			}
			catch (e:Exception)
			{
				trace('Could not copy "$src" to "$dst". (${e.message})');
				ok = false;
			}
		}
		return ok;
	}

	static function copyDirectory(from:String, to:String):Bool
	{
		var ok:Bool = true;
		try
		{
			if (!FileSystem.exists(to))
				FileSystem.createDirectory(to);

			for (name in FileSystem.readDirectory(from))
			{
				final src:String = Path.addTrailingSlash(from) + name;
				final dst:String = Path.addTrailingSlash(to) + name;
				if (FileSystem.isDirectory(src))
					ok = copyDirectory(src, dst) && ok;
				else
					File.copy(src, dst);
			}
		}
		catch (e:Exception)
		{
			trace('Could not copy "$from" to "$to". (${e.message})');
			ok = false;
		}
		return ok;
	}
	#end
}

#if android
@:runtimeValue
enum abstract StorageType(String) from String to String
{
	public static inline var DEFAULT:String = "EXTERNAL";

	var EXTERNAL_OBB = "EXTERNAL_OBB";
	var EXTERNAL_MEDIA = "EXTERNAL_MEDIA";
	var EXTERNAL = "EXTERNAL";

	static function getAndroidRoot():String
	{
		var dir:String = LimeSystem.applicationStorageDirectory;
		var index:Int = dir.indexOf('/Android/');
		return index > 0 ? dir.substr(0, index) : '/storage/emulated/0';
	}

	static function getPackageName():String
		return lime.app.Application.current.meta.get('packageName');

	static function getFileMeta():String
		return lime.app.Application.current.meta.get('file');

	public static function legacyDataPath():String
		return '${getAndroidRoot()}/Android/data/${getPackageName()}/files';

	public static function fromStr(str:String):StorageType
	{
		final root:String = getAndroidRoot();

		return switch (str)
		{
			case "EXTERNAL_DATA": '$root/.${getFileMeta()}'; // legacy value, data dir is gone
			case "EXTERNAL_OBB": '$root/Android/obb/${getPackageName()}';
			case "EXTERNAL_MEDIA": '$root/Android/media/${getPackageName()}';
			case "EXTERNAL": '$root/.${getFileMeta()}';
			default: '$root/.${str}';
		}
	}

	public static function fromStrForce(str:String):StorageType
	{
		final root:String = getAndroidRoot();

		return switch (str)
		{
			case "EXTERNAL_DATA": '$root/.${getFileMeta()}'; // legacy value, data dir is gone
			case "EXTERNAL_OBB": '$root/Android/obb/${getPackageName()}';
			case "EXTERNAL_MEDIA": '$root/Android/media/${getPackageName()}';
			case "EXTERNAL": '$root/.${getFileMeta()}';
			default: '$root/.${str}';
		}
	}
}
#end
