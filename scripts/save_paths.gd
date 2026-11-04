extends RefCounted
## Where the save files live (settings, progress, run stats).
##
## Normal play uses user://. Tests, screenshots, the playtest bot and smoke tests run
## "isolated": started on a res://tools/ scene, or with --isolated, --smoketest or --shot...
## They start from a fresh state and keep their files in a folder of their own,
## user://isolated/<process id>/, so they never read or overwrite the player's progress and
## settings, and parallel runs don't share files. The folder is deleted when the run quits;
## leftovers from crashed runs are swept on the next isolated start.
##
## Used through a preload (const SavePaths := preload("res://scripts/save_paths.gd")), not a
## class_name, so it also works in headless runs before the editor has rescanned the project.

const ISOLATED_ROOT := "user://isolated"
const STALE_SECONDS := 6 * 3600


static func is_isolated() -> bool:
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tools/"):
			return true
	for a in OS.get_cmdline_user_args():
		if a == "--isolated" or a == "--smoketest" or a.begins_with("--shot"):
			return true
	return false


## The path for one save file, e.g. path("settings.cfg").
static func path(file: String) -> String:
	if not is_isolated():
		return "user://" + file
	var dir := _run_dir()
	if not DirAccess.dir_exists_absolute(dir):
		_sweep_stale()
		DirAccess.make_dir_recursive_absolute(dir)
		var marker := FileAccess.open(dir + "/.run", FileAccess.WRITE)   # dates the folder for _sweep_stale
		if marker:
			marker.store_string(str(Time.get_unix_time_from_system()))
	return dir + "/" + file


## Delete this isolated run's folder (call on quit). Does nothing in normal play.
static func clean_up() -> void:
	if is_isolated():
		_remove_dir(_run_dir())


static func _run_dir() -> String:
	return "%s/%d" % [ISOLATED_ROOT, OS.get_process_id()]


## Remove folders left behind by isolated runs that crashed or were killed.
static func _sweep_stale() -> void:
	var root := DirAccess.open(ISOLATED_ROOT)
	if root == null:
		return
	var now := Time.get_unix_time_from_system()
	for d in root.get_directories():
		var dir := ISOLATED_ROOT + "/" + d
		var newest := 0
		for f in DirAccess.get_files_at(dir):
			newest = maxi(newest, FileAccess.get_modified_time(dir + "/" + f))
		if newest > 0 and now - newest > STALE_SECONDS:   # empty folders are left alone
			_remove_dir(dir)


static func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
