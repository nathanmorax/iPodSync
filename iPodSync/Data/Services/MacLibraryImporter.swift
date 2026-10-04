//
//  MacLibraryImporter.swift
//  iPodSync
//
//  Convierte un archivo de audio de la Mac en una canción de la biblioteca: lee sus datos
//  (título, artista, álbum, género, pista, año, duración, portada) con AVFoundation y guarda
//  el permiso para volver a leer el archivo cuando haya que copiarlo al iPod.
//

import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MacLibraryImporter {
    /// Formatos que reproduce un iPod (5.ª generación / classic).
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff"]

    enum ImportError: LocalizedError {
        case unsupported(name: String, ext: String)
        case unreadable(name: String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name, let ext):
                return "“\(name)”: el iPod no reproduce archivos .\(ext). Usa MP3 o M4A."
            case .unreadable(let name):
                return "“\(name)”: no se pudo leer como audio (¿archivo dañado o incompleto?)."
            }
        }
    }

    static func importFile(_ url: URL) async throws -> Song {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw ImportError.unsupported(name: name, ext: ext) }

        // Archivos elegidos con el diálogo traen permiso "security-scoped"; los arrastrados ya lo tienen.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        let asset = AVURLAsset(url: url)
        let loaded: (CMTime, [AVMetadataItem], [AVMetadataItem])
        do {
            loaded = try await asset.load(.duration, .commonMetadata, .metadata)
        } catch {
            throw ImportError.unreadable(name: name)
        }
        let (duration, common, all) = loaded
        let seconds = duration.seconds.isFinite ? duration.seconds : 0
        guard seconds > 0 else { throw ImportError.unreadable(name: name) }

        let items = common + all
        let title = await string(items, [.commonIdentifierTitle, .id3MetadataTitleDescription, .iTunesMetadataSongName])
        let artist = await string(items, [.commonIdentifierArtist, .id3MetadataLeadPerformer, .iTunesMetadataArtist])
        let album = await string(items, [.commonIdentifierAlbumName, .id3MetadataAlbumTitle, .iTunesMetadataAlbum])
        let genre = await string(items, [.id3MetadataContentType, .iTunesMetadataUserGenre, .quickTimeMetadataGenre])
        let year = await yearValue(items)
        let track = await trackValue(items)
        let artwork = await data(items, [.commonIdentifierArtwork, .id3MetadataAttachedPicture, .iTunesMetadataCoverArt])
            .flatMap { thumbnail($0) }

        let key = (album ?? artist ?? name)
        let hash = key.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }

        return Song(title: title ?? url.deletingPathExtension().lastPathComponent,
                    artist: artist ?? "Artista desconocido",
                    sizeMB: max(0.1, Double(bytes) / 1_048_576),
                    artworkHue: Double(hash % 360) / 360,
                    isOnDevice: false,
                    albumName: album,
                    genre: genre.map(cleanGenre),
                    trackNumber: track,
                    year: year,
                    durationSeconds: seconds,
                    fileFormat: ext,
                    fileURL: url,
                    bookmark: bookmark,
                    artworkData: artwork)
    }

    // MARK: - Metadatos

    private static func first(_ items: [AVMetadataItem], _ ids: [AVMetadataIdentifier]) -> [AVMetadataItem] {
        ids.flatMap { id in items.filter { $0.identifier == id } }
    }

    private static func string(_ items: [AVMetadataItem], _ ids: [AVMetadataIdentifier]) async -> String? {
        for item in first(items, ids) {
            if let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func data(_ items: [AVMetadataItem], _ ids: [AVMetadataIdentifier]) async -> Data? {
        for item in first(items, ids) {
            if let value = try? await item.load(.dataValue), !value.isEmpty { return value }
        }
        return nil
    }

    private static func yearValue(_ items: [AVMetadataItem]) async -> Int? {
        let ids: [AVMetadataIdentifier] = [.id3MetadataYear, .id3MetadataRecordingTime,
                                           .iTunesMetadataReleaseDate, .commonIdentifierCreationDate]
        guard let text = await string(items, ids) else { return nil }
        let digits = text.prefix { $0.isNumber }
        guard digits.count >= 4, let year = Int(digits.prefix(4)) else { return nil }
        return year
    }

    /// ID3: "3/12". iTunes (M4A): 8 bytes, la pista en los bytes 2–3.
    private static func trackValue(_ items: [AVMetadataItem]) async -> Int? {
        if let text = await string(items, [.id3MetadataTrackNumber]),
           let n = Int(text.split(separator: "/").first ?? "") {
            return n
        }
        if let raw = await data(items, [.iTunesMetadataTrackNumber]), raw.count >= 4 {
            let bytes = [UInt8](raw)
            let n = Int(bytes[2]) << 8 | Int(bytes[3])
            return n > 0 ? n : nil
        }
        return nil
    }

    /// ID3 a veces guarda el género como "(17)" o "(17)Rock".
    private static func cleanGenre(_ raw: String) -> String {
        if raw.hasPrefix("("), let close = raw.firstIndex(of: ")") {
            let rest = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? raw : rest
        }
        return raw
    }

    // MARK: - Portada

    /// Portada reducida a JPEG de ~600 px (nítida en la cuadrícula de 2 columnas en pantallas Retina).
    static func thumbnail(_ data: Data, maxPixel: Int = 600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
