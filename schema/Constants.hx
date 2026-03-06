package schema;

enum abstract RoomName(String) from String to String {
	var LOBBY = "lobby";
	var QUEUE = "queue";
	var CHAR_SELECT = "char_select";
	var CHAR_SELECT_PRIVATE = "char_select_private";
	var GAME = "game_room";
}
