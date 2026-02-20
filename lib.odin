package json_serializer

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:math"
import "core:mem"
import "core:reflect"
import "core:strings"

@(require_results)
to_json :: proc(value: any, alloc: mem.Allocator) -> string {
    builder := strings.builder_make(alloc)

    write_value(&builder, value)

    return strings.to_string(builder)
}

write_value :: proc(builder: ^strings.Builder, value: any) {
    type_info := runtime.type_info_base(type_info_of(value.id))

    #partial switch variant in type_info.variant {
    // Primitives
    case runtime.Type_Info_String, runtime.Type_Info_Rune:
        write_string(builder, value)
    case runtime.Type_Info_Integer:
        write_int(builder, value)
    case runtime.Type_Info_Float:
        write_float(builder, value)
    case runtime.Type_Info_Boolean:
        write_bool(builder, value)
    // Compound Types
    case runtime.Type_Info_Struct:
        write_struct(builder, variant, value)
    case runtime.Type_Info_Union:
        write_union(builder, variant, value)
    // Collections
    case runtime.Type_Info_Array:
        write_array(builder, variant, value)
    case runtime.Type_Info_Slice:
        write_slice(builder, variant, value)
    case runtime.Type_Info_Dynamic_Array:
        write_slice(builder, runtime.Type_Info_Slice(variant), value)
    case runtime.Type_Info_Map:
        write_map(builder, variant, value)
    // Enums
    case runtime.Type_Info_Enum:
        write_enum(builder, variant, value)
    case:
        unimplemented(fmt.tprintf("%v %v", value, type_info))

    // Invalid
    case runtime.Type_Info_Named:
        panic("reflect.type_info_base is broken?")
    }
}

write_enum :: proc(builder: ^strings.Builder, info: runtime.Type_Info_Enum, value: any) {
    active_variant: runtime.Type_Info_Enum_Value

    switch type in (any{value.data, info.base.id}) {
    case int:     active_variant = auto_cast type
    case uint:    active_variant = auto_cast type
    case i8:      active_variant = auto_cast type
    case u8:      active_variant = auto_cast type
    case i16:     active_variant = auto_cast type
    case u16:     active_variant = auto_cast type
    case i32:     active_variant = auto_cast type
    case u32:     active_variant = auto_cast type
    case i64:     active_variant = auto_cast type
    case u64:     active_variant = auto_cast type
    case i16le:   active_variant = auto_cast type
    case u16le:   active_variant = auto_cast type
    case i32le:   active_variant = auto_cast type
    case u32le:   active_variant = auto_cast type
    case i64le:   active_variant = auto_cast type
    case u64le:   active_variant = auto_cast type
    case i16be:   active_variant = auto_cast type
    case u16be:   active_variant = auto_cast type
    case i32be:   active_variant = auto_cast type
    case u32be:   active_variant = auto_cast type
    case i64be:   active_variant = auto_cast type
    case u64be:   active_variant = auto_cast type
    case uintptr: active_variant = auto_cast type
    }

    for value, i in info.values {
        if value == active_variant {
            write_string(builder,{&info.names[i], typeid_of(string)})
            return
        }
    }
    
    write_int(builder,i64(active_variant))
}


write_union :: proc(builder: ^strings.Builder, info: runtime.Type_Info_Union, value: any) {
    tag: int

    tag_ptr := rawptr(info.tag_offset + uintptr(value.data))
    switch i in (any{tag_ptr, info.tag_type.id}) {
        case u8:  tag = int(i)
        case i8:  tag = int(i)
        case u16: tag = int(i)
        case i16: tag = int(i)
        case u32: tag = int(i)
        case i32: tag = int(i)
        case u64: tag = int(i)
        case i64: tag = int(i)
        case: fmt.panicf("Unhandled tag type %v", info.tag_type.id)
    }

    if !info.no_nil {
        tag -= 1
    }

    if tag == -1 {
        fmt.sbprint(builder, "null")
        return
    }

    active_variant_type := info.variants[tag]
    variant_any := any{value.data, active_variant_type.id}

    write_value(builder, variant_any)
}

write_map :: proc(builder: ^strings.Builder, info: runtime.Type_Info_Map, value: any) {
    fmt.sbprint(builder, '{')
    raw := (^runtime.Raw_Map)(value.data)^
    map_size := runtime.map_cap(raw)

    key_info := info.map_info.ks
    value_info := info.map_info.vs

    keys, values, hashes, _, _ := runtime.map_kvh_data_dynamic(raw, info.map_info)

    key_type_info := runtime.type_info_base(type_info_of(info.key.id))

    if key_type_info.id != string {
        fmt.panicf("Can only write maps with string keys, got %v", key_type_info.id)
    }

    iter := 0

    for cell_index in 0 ..< map_size {
        if !runtime.map_hash_is_valid(hashes[cell_index]) {
            continue
        }

        if iter != 0 {
            fmt.sbprint(builder, ',')
        }

        key_ptr := rawptr(runtime.map_cell_index_dynamic(keys, key_info, uintptr(cell_index)))
        value_ptr := rawptr(
            runtime.map_cell_index_dynamic(values, value_info, uintptr(cell_index)),
        )


        key := any{key_ptr, key_type_info.id}
        value := any{value_ptr, info.value.id}

        write_string(builder, key)
        fmt.sbprint(builder, ':')
        write_value(builder, value)

        iter += 1
    }
    fmt.sbprint(builder, '}')
}

write_slice :: proc(builder: ^strings.Builder, info: runtime.Type_Info_Slice, value: any) {
    fmt.sbprint(builder, '[')

    elem_type := info.elem.id
    elem_size := info.elem_size

    slice_data := (^runtime.Raw_Slice)(value.data)

    for i in 0 ..< slice_data.len {
        elem_ptr := uintptr(slice_data.data) + uintptr(elem_size * i)
        if i != 0 {
            fmt.sbprint(builder, ',')
        }

        write_value(builder, any{data = rawptr(elem_ptr), id = elem_type})
    }

    fmt.sbprint(builder, ']')
}

write_array :: proc(builder: ^strings.Builder, info: runtime.Type_Info_Array, value: any) {
    fmt.sbprint(builder, '[')

    elem_type := info.elem.id
    elem_size := info.elem_size
    elem_count := info.count

    for i in 0 ..< elem_count {
        elem_ptr := uintptr(value.data) + uintptr(elem_size * i)
        if i != 0 {
            fmt.sbprint(builder, ',')
        }

        write_value(builder, any{data = rawptr(elem_ptr), id = elem_type})

    }

    fmt.sbprint(builder, ']')
}

write_struct :: proc(builder: ^strings.Builder, info: runtime.Type_Info_Struct, value: any) {
    fmt.sbprint(builder, '{')

    for field_index in 0 ..< info.field_count {
        if field_index != 0 {
            fmt.sbprint(builder, ',')
        }
        write_string(builder, info.names[field_index])
        fmt.sbprint(builder, ':')

        field_ptr := uintptr(value.data) + info.offsets[field_index]
        field_type := info.types[field_index].id

        write_value(builder, any{data = rawptr(field_ptr), id = field_type})
    }

    fmt.sbprint(builder, '}')
}

write_bool :: proc(builder: ^strings.Builder, value: any) {
    is_true: bool
    switch type in value {
        case b8:   is_true = bool(type)
        case b16:  is_true = bool(type)
        case b32:  is_true = bool(type)
        case b64:  is_true = bool(type)
        case bool: is_true = bool(type)
        case: fmt.panicf("Non-boolean type '%v' made it into `write_bool`", value.id)
    }

    fmt.sbprint(builder, "true" if is_true else "false")
}

write_int :: proc(builder: ^strings.Builder, value: any) {
    switch type in value {
    case int, uint, 
        u8, u16,   u32,   u64,   u128,
            u16be, u32be, u64be, u128be,
            u16le, u32le, u64le, u128le,
        i8, i16,   i32,   i64,   i128,
            i16be, i32be, i64be, i128be,
            i16le, i32le, i64le, i128le:
        fmt.sbprintf(builder, "%d", type)
    case:
        fmt.panicf("Non-integer type '%v' made it into `write_int`", value.id)
    }
}

write_float :: proc(builder: ^strings.Builder, value: any) {
    f64_val: f64
    switch type in value {
        case f16:   f64_val = f64(type)
        case f32:   f64_val = f64(type)
        case f64:   f64_val = f64(type)
        case f16le: f64_val = f64(type)
        case f32le: f64_val = f64(type)
        case f64le: f64_val = f64(type)
        case f16be: f64_val = f64(type)
        case f32be: f64_val = f64(type)
        case f64be: f64_val = f64(type)
        case: fmt.panicf("Non-float type '%v' made it into `write_float`", value.id)
    }

    switch math.classify(f64_val) {
    case .Inf:
        fmt.sbprint(builder, "\"Infinity\"")
    case .Neg_Inf:
        fmt.sbprint(builder, "\"-Infinity\"")
    case .NaN:
        fmt.sbprint(builder, "\"NaN\"")
    case .Normal, .Subnormal, .Zero, .Neg_Zero:
        fmt.sbprint(builder, f64_val)
    }
}

write_string :: proc(builder: ^strings.Builder, value: any) {
    switch type in value {
    case string, cstring, string16, cstring16:
        fmt.sbprintf(builder, "%q", type)
    case rune:
        fmt.sbprint(builder, '"')
        writer := strings.to_writer(builder)
        io.write_escaped_rune(writer, type, '"')
        fmt.sbprint(builder, '"')
    case:
        fmt.panicf("Non-string type '%v' made it into `write_string`", value.id)
    }
}

