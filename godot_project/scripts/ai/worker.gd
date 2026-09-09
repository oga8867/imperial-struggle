extends Node

func _ready() -> void:
	# 이 장면은 게임 창 없이 시작된다. 입력은 비공개 정보가 제거된 관찰뿐이다.
	var args=OS.get_cmdline_user_args()
	var index=args.find("--ai-worker")
	if index<0 or index+1>=args.size(): get_tree().quit(2); return
	var path=args[index+1]
	var job=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not job is Dictionary: get_tree().quit(2); return
	var search=preload("res://scripts/ai/search.gd").new()
	var result=search.run(job,func(progress): _write(path+".result",progress,job.get("id",""),false))
	_write(path+".result",result,job.get("id",""),true)
	get_tree().quit()

func _write(path: String,result: Dictionary,id: String,done: bool) -> void:
	result=result.duplicate(true)
	result.job_id=id
	result.done=done
	var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify(result))
	file.close()
	DirAccess.rename_absolute(path+".tmp",path)
