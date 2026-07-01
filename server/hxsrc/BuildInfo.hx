class BuildInfo {
	public static macro function timestamp():haxe.macro.Expr.ExprOf<String> {
		var now = Date.now();
		var stamp = DateTools.format(now, "%Y-%m-%d %H:%M:%S");
		return macro $v{stamp};
	}
}
