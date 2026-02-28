package ui;

import entities.Inventory;
import entities.Inventory.InventoryItem;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;

class InventoryHUD extends FlxSpriteGroup {
	static inline var SLOT_SIZE:Int = 16;
	static inline var SLOT_GAP:Int = 2;
	static inline var MARGIN:Int = 4;

	var inventory:Inventory;
	var slots:Array<FlxSprite> = [];

	public function new(inventory:Inventory) {
		super();
		this.inventory = inventory;
		scrollFactor.set(0, 0);

		var startX = FlxG.width - MARGIN - (SLOT_SIZE + SLOT_GAP) * Inventory.MAX_SLOTS + SLOT_GAP;
		for (i in 0...Inventory.MAX_SLOTS) {
			var slot = new FlxSprite(startX + i * (SLOT_SIZE + SLOT_GAP), MARGIN);
			slot.makeGraphic(SLOT_SIZE, SLOT_SIZE, FlxColor.fromRGB(30, 30, 30));
			add(slot);
			slots.push(slot);
		}

		inventory.onChange.add(redraw);
		redraw();
	}

	function redraw() {
		for (i in 0...Inventory.MAX_SLOTS) {
			if (i < inventory.items.length) {
				var color = switch (inventory.items[i]) {
					case Rock: FlxColor.GRAY;
					case Fish: FlxColor.GREEN;
				};
				slots[i].makeGraphic(SLOT_SIZE, SLOT_SIZE, color);
			} else {
				slots[i].makeGraphic(SLOT_SIZE, SLOT_SIZE, FlxColor.fromRGB(30, 30, 30));
			}
		}
	}

	override function destroy() {
		inventory.onChange.remove(redraw);
		super.destroy();
	}
}
