// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favourites_service.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FavoriteItemAdapter extends TypeAdapter<FavoriteItem> {
  @override
  final int typeId = 0;

  @override
  FavoriteItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FavoriteItem(
      id: fields[0] as String,
      title: fields[1] as String,
      url: fields[2] as String?,
      thumb: fields[3] as String?,
      author: fields[4] as String?,
      mediatype: fields[5] as String?,
      formats: (fields[6] as List).cast<String>(),
      files: (fields[7] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, String>())
          ?.toList(),
    );
  }

  @override
  void write(BinaryWriter writer, FavoriteItem obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.thumb)
      ..writeByte(4)
      ..write(obj.author)
      ..writeByte(5)
      ..write(obj.mediatype)
      ..writeByte(6)
      ..write(obj.formats)
      ..writeByte(7)
      ..write(obj.files);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
