package json_serializer

import "core:os"
import "core:encoding/uuid"
import "core:math/rand"
import "base:runtime"

Enemy_Type :: enum {
    Zombie,
    Skeleton,
    Spider
}

Player :: struct {
    health: f64,
    name: string,
    inventory: []Item,
    uuid: [16]u8,
}

Enemy :: struct {
    health: f64,
    uuid: [16]u8,
    type: Enemy_Type,
    alive: bool
}

Item :: struct {
    uses: int,
    name: string
}

World :: struct {
    players: map[string]Player,
    time: u128,
    enemies: [dynamic]Enemy,
}

main :: proc() {
    world := make_world(context.allocator)
    
    json_data := to_json(world, context.allocator)
    _ = os.write_entire_file("out.json", json_data)
}

make_world :: proc(allocator: runtime.Allocator) -> World {
    world: World

    world.time = rand.uint128()
    
    enemy_count := rand.int_range(4,10)
    world.enemies.allocator = allocator
    for _ in 0..<enemy_count {
        append(&world.enemies, make_enemy(allocator))
    }
    
    player_count := rand.int_range(1,5)
    world.players.allocator = allocator
    for _ in 0..< enemy_count {
        player := make_player(allocator)
        world.players[player.name] = player
    }
    
    return world
}

make_enemy :: proc(alloc: runtime.Allocator) -> Enemy {
    enemy: Enemy
    
    enemy.alive = rand.float32() >= 0.5
    enemy.health = f64(rand.int32_range(10,100))
    enemy.type = rand.choice_enum(Enemy_Type)
    enemy.uuid = auto_cast uuid.generate_v4()
    
    return enemy
}

make_player :: proc(alloc: runtime.Allocator) -> Player {
    player: Player
    
    player.health = f64(rand.int32_range(10,100))
    player.uuid = auto_cast uuid.generate_v4()
    player.name = rand.choice([]string {
        "Adam",
        "Barry",
        "Carl",
        "Daisy",
        "Eli",
        "Fred",
        "Garry",
        "Hank",
        "Ivan",
        "Jasmine",
        "Katherine",
        "Lucy",
        "Manny",
        "Niko",
        "Ophelia",
        "Parry",
        "Q Name",
        "RATS",
        "Susie",
        "Tommy",
        "U Name",
        "Victor",
        "Wanda",
        "X Name",
        "Y Name",
        "Zachary"
    })
    
    item_count := rand.int32_range(0,5)
    player.inventory = make([]Item, item_count, alloc)
    for &item in player.inventory {
        item = make_item()
    }
    
    return player
}

make_item :: proc() -> Item {
    item: Item
    
    if rand.float32() > 0.5 {
        item.uses = rand.int_range(50,200)
        item.name = rand.choice([]string{
            "Iron Axe",
            "Bow",
            "Steel Broadsword",
            "Steel Shovel",
            "Bronze Shield",
            "Iron Helmet"
        })
    } else {
        item.uses = rand.int_range(1,6)
        item.name = rand.choice([]string{
            "Potion",
            "Spell Tome",
            "Bread",
            "Rope",
            "Sticks",
            "Iron Bar"
        })
    }
    
    return item
}