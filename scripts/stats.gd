class_name Stats
extends RefCounted
## Layered stat pipeline:  value = (base + flat) * (1 + additive%) * multiplicative
##
## "flat"  -> +N to the base          (e.g. +20 max HP)
## "add"   -> +N% summed additively   (e.g. three +10% damage tomes = +30%)
## "mult"  -> multiplied together     (e.g. cooldown x0.9 x0.9)

signal changed(stat: String)

var _base := {}
var _flat := {}
var _add := {}
var _mult := {}


func define(stat: String, base: float) -> void:
	_base[stat] = base
	_flat[stat] = 0.0
	_add[stat] = 0.0
	_mult[stat] = 1.0


func has_stat(stat: String) -> bool:
	return _base.has(stat)


func apply(stat: String, op: String, amount: float) -> void:
	if not _base.has(stat):
		push_warning("Stats: unknown stat '%s'" % stat)
		return
	match op:
		"flat":
			_flat[stat] += amount
		"add":
			_add[stat] += amount
		"mult":
			_mult[stat] *= amount
		_:
			push_warning("Stats: unknown op '%s'" % op)
			return
	changed.emit(stat)


func value(stat: String) -> float:
	return (_base[stat] + _flat[stat]) * maxf(0.0, 1.0 + _add[stat]) * _mult[stat]


## The stat's starting value, before anything was applied.
func base_of(stat: String) -> float:
	return float(_base.get(stat, 0.0))


func names() -> Array:
	return _base.keys()
