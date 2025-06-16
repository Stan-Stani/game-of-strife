extends Node

var colony

# Multiplayer persistence across scenes
var multiplayer_peer: ENetMultiplayerPeer = null
var is_host: bool = false
var is_connected: bool = false

func set_multiplayer_peer(peer: ENetMultiplayerPeer, host: bool = false):
	multiplayer_peer = peer
	is_host = host
	is_connected = true
	multiplayer.multiplayer_peer = peer
	print("GameState: Multiplayer peer set (host: " + str(host) + ")")

func get_multiplayer_peer() -> ENetMultiplayerPeer:
	return multiplayer_peer

func clear_multiplayer():
	if multiplayer_peer:
		multiplayer_peer.close()
	multiplayer_peer = null
	is_host = false
	is_connected = false
	multiplayer.multiplayer_peer = null
	print("GameState: Multiplayer cleared")

func restore_multiplayer_peer():
	if multiplayer_peer and is_connected:
		multiplayer.multiplayer_peer = multiplayer_peer
		print("GameState: Multiplayer peer restored")
		return true
	return false
