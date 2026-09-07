#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera Modular_3D/textures/manifest.json escaneando TODAS las imágenes bajo
Modular_3D/textures/ (incluyendo cualquier nivel de subcarpetas: marca ->
colección -> archivo), calculando un color promedio real por imagen (para
el swatch de vista previa) y derivando un nombre legible a partir del
nombre de archivo.

Uso (después de agregar/quitar carpetas de marcas en Modular_3D/textures/):
    python3 Modular_3D/textures/generar_manifiesto.py

Requiere Pillow (pip install Pillow). No se ejecuta nunca desde SketchUp/
Ruby -- es una herramienta de mantenimiento para cuando se suman más
texturas, igual que un script de build.
"""
import json
import os
import re
import sys
import unicodedata

from PIL import Image

TEXTURES_DIR = os.path.dirname(os.path.abspath(__file__))
MANIFEST_PATH = os.path.join(TEXTURES_DIR, 'manifest.json')
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp'}

# Entradas curadas de la biblioteca original (7 texturas genéricas, no de
# fabricante): se conservan tal cual, con su id/nombre/color a mano, en vez
# de regenerarlas a partir del nombre de archivo.
CURATED_IDS = {
    'blanco_liso', 'blanco_nube', 'negro_mate', 'gris_antracita',
    'roble_claro', 'nogal_oscuro', 'wengue'
}

BRANDS = [
    'DURAPLAC', 'FABLAC', 'FIBRAPLAC', 'GUARARAPES', 'MASISA',
    'PELIKANO', 'TABLEROS HISPANOS', 'VESTO'
]


def slugify(text):
    normalized = unicodedata.normalize('NFKD', text)
    ascii_text = normalized.encode('ascii', 'ignore').decode('ascii')
    ascii_text = re.sub(r'[^a-zA-Z0-9]+', '_', ascii_text).strip('_').lower()
    return ascii_text or 'textura'


# Algunas carpetas de marca usan una abreviatura distinta en el propio
# nombre de archivo (ej. la carpeta "FABLAC" trae archivos "...-FAPLAC.jpg",
# y "TABLEROS HISPANOS" trae "...-TH.jpg") -- se prueban todos los alias
# conocidos de esa marca, no solo el nombre de carpeta.
BRAND_FILE_ALIASES = {
    'FABLAC': ['FABLAC', 'FAPLAC'],
    'TABLEROS HISPANOS': ['TABLEROS HISPANOS', 'TH'],
}


def strip_brand_suffix(stem, brand):
    """'Santorini-MASISA' / 'Roble miel DURAPLAC' -> 'Santorini' / 'Roble miel'"""
    for alias in BRAND_FILE_ALIASES.get(brand, [brand]):
        pattern = re.compile(r'[\s_-]*' + re.escape(alias) + r'\s*$', re.IGNORECASE)
        stripped = pattern.sub('', stem).strip()
        if stripped != stem:
            return stripped
    return stem


def humanize(name):
    """CamelCase / snake_case -> palabras separadas, con mayúscula inicial."""
    name = name.replace('_', ' ')
    name = re.sub(r'(?<=[a-záéíóúñ])(?=[A-ZÁÉÍÓÚÑ])', ' ', name)
    name = re.sub(r'\s+', ' ', name).strip()
    return ' '.join(word[:1].upper() + word[1:] for word in name.split(' ') if word)


def average_color_hex(path):
    try:
        with Image.open(path) as img:
            small = img.convert('RGB').resize((32, 32))
            pixels = list(small.getdata())
            r = sum(p[0] for p in pixels) // len(pixels)
            g = sum(p[1] for p in pixels) // len(pixels)
            b = sum(p[2] for p in pixels) // len(pixels)
            return '#{:02x}{:02x}{:02x}'.format(r, g, b)
    except Exception as error:  # noqa: BLE001 -- reportar y seguir con el resto
        print('  AVISO: no se pudo leer {} ({})'.format(path, error), file=sys.stderr)
        return '#c9a880'


def build_entries():
    entries = []
    seen_ids = set()
    for brand in BRANDS:
        brand_dir = os.path.join(TEXTURES_DIR, brand)
        if not os.path.isdir(brand_dir):
            continue
        for root, _dirs, files in os.walk(brand_dir):
            rel_root = os.path.relpath(root, TEXTURES_DIR)
            collection = None
            parts = [p for p in rel_root.split(os.sep) if p not in ('.', brand)]
            if parts:
                collection = ' / '.join(parts)
            for filename in sorted(files):
                stem, ext = os.path.splitext(filename)
                if ext.lower() not in IMAGE_EXTS:
                    continue
                full_path = os.path.join(root, filename)
                rel_path = os.path.relpath(full_path, TEXTURES_DIR).replace(os.sep, '/')
                clean_stem = strip_brand_suffix(stem, brand)
                display_color = humanize(clean_stem) or humanize(stem)
                label = ' · '.join([brand] + (parts or []) + [display_color])
                base_id = slugify(rel_path.rsplit('.', 1)[0])
                texture_id = base_id
                suffix = 2
                while texture_id in seen_ids:
                    texture_id = '{}_{}'.format(base_id, suffix)
                    suffix += 1
                seen_ids.add(texture_id)
                entries.append({
                    'id': texture_id,
                    'name': label,
                    'file': rel_path,
                    'defaultScale': 600,
                    'defaultColor': average_color_hex(full_path),
                    'brand': brand,
                    'collection': collection
                })
    entries.sort(key=lambda item: (item['brand'], item['collection'] or '', item['name']))
    return entries


def load_curated():
    if not os.path.exists(MANIFEST_PATH):
        return []
    with open(MANIFEST_PATH, 'r', encoding='utf-8') as handle:
        data = json.load(handle)
    return [item for item in data.get('textures', []) if item.get('id') in CURATED_IDS]


def main():
    curated = load_curated()
    generated = build_entries()
    manifest = {'textures': curated + generated}
    with open(MANIFEST_PATH, 'w', encoding='utf-8') as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
    print('Listo: {} texturas curadas + {} de fabricante = {} en total.'.format(
        len(curated), len(generated), len(manifest['textures'])
    ))


if __name__ == '__main__':
    main()
