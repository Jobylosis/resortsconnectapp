import re
import easyocr

reader = easyocr.Reader(['en'], gpu=False)
results = reader.readtext('tester_id.jpg')

def get_reading_order_lines(results):
    items = []
    for r in results:
        try:
            box = r[0]
            text = r[1].strip()
            if not text:
                continue
            min_x = min(pt[0] for pt in box)
            min_y = min(pt[1] for pt in box)
            max_y = max(pt[1] for pt in box)
            items.append({'text': text, 'box': box, 'min_x': min_x, 'min_y': min_y, 'max_y': max_y, 'mid_y': (min_y + max_y) / 2})
        except Exception:
            continue
    items.sort(key=lambda item: item['mid_y'])
    grouped_lines = []
    current_line = []
    for item in items:
        if not current_line:
            current_line.append(item)
        else:
            curr_mid = sum(it['mid_y'] for it in current_line) / len(current_line)
            curr_h = sum(it['max_y'] - it['min_y'] for it in current_line) / len(current_line)
            if abs(item['mid_y'] - curr_mid) < max(curr_h * 0.5, 12):
                current_line.append(item)
            else:
                current_line.sort(key=lambda it: it['min_x'])
                grouped_lines.append(current_line)
                current_line = [item]
    if current_line:
        current_line.sort(key=lambda it: it['min_x'])
        grouped_lines.append(current_line)
    return [' '.join(it['text'] for it in l) for l in grouped_lines]

lines = get_reading_order_lines(results)
print("ORDERED LINES:")
for i, l in enumerate(lines):
    print(f"{i}: {l}")

ID_FIELD_ANCHORS = {
    "Philippine National ID (PhilSys)": {
        "last":   ["APELLIDO", "LASTNAME", "APELYIDO", "APLEYIDO", "APEYIDO", "LESTNAME", "LSTNAME"],
        "first":  ["MGAPANGALAN", "GIVENNAMES", "GIVENNAME", "GIVEN", "PANGALAN"],
        "middle": ["GITNANGNAPELYIDO", "GITNANGNAAPILYIDO", "MIDDLENAME", "MIDDLEMAME", "GITNANGAPELYIDO", "GIINANGAPELYIDO", "GITNANG", "GIINANG"],
    },
}

ALL_FIELD_LABELS = [
    "APELLIDO", "APELYIDO", "APLEYIDO", "APEYIDO", "MGAPANGALAN", "GIVENNAMES", "GIVENNAME", "FIRSTNAME",
    "GITNANGNAPELYIDO", "GITNANGNAAPILYIDO", "GITNANGAPELYIDO", "GIINANGAPELYIDO", "GITNANG", "GIINANG",
    "MIDDLENAME", "MIDDLEMAME", "MIDDLEINITIAL", "SURNAME", "LASTNAME", "LESTNAME", "LSTNAME",
    "PETSAMGAKAPANGANAKAN", "PETSANGKAPANGANATON", "DATEOFBIRTH", "DAREOFBIRTH",
    "TIRAHAN", "ADDRESS", "ADDRES", "SEX", "BLOODTYPE", "HEIGHT", "NATIONALITY", "CIVILSTATUS",
    "PANGALAN", "GITNANGPANGALAN",
]

def extract_field_region(lines_clean, anchor_labels, all_labels):
    region_parts = []
    collecting = False
    
    label_noise = set(all_labels) | set(anchor_labels) | {
        'APELYIDO', 'APELLIDO', 'APLEYIDO', 'APEYIDO', 'APELIDO', 'LAST', 'LEST', 'LST', 'NAME', 'NANE', 'LASTNAME', 'LESTNAME', 'SURNAME', 'SUMAME',
        'MGA', 'PANGALAN', 'MGAPANGALAN', 'GIVEN', 'NAMES', 'GIVENNAMES', 'FIRST', 'FIRSTNAME', 'UNANG',
        'GITNANG', 'GIINANG', 'GITANG', 'GITNANGAPELYIDO', 'GIINANGAPELYIDO', 'MIDDLE', 'MIDDLENAME', 'MIDDLEMAME', 'MAME', 'INITIAL', 'MIDDLEINITIAL',
        'PETSA', 'KAPANGANAKAN', 'KAPANGANATON', 'DATE', 'DARE', 'BIRTH', 'DOB', 'DATEOFBIRTH', 'DAREOFBIRTH',
        'TIRAHAN', 'ADDRESS', 'ADDRES', 'SEX', 'KASARIAN', 'CIVIL', 'STATUS'
    }

    is_surname_search = any(a in ["LASTNAME", "APELYIDO", "APELLIDO", "SURNAME", "APLEYIDO"] for a in anchor_labels)

    for line in lines_clean:
        line_u = line.upper()
        stripped = re.sub(r'[^A-Z0-9]', '', line_u)
        
        is_middle_line = any(m in stripped for m in ["GITNANG", "GIINANG", "MIDDLENAME", "MIDDLEMAME"])
        if is_surname_search and is_middle_line:
            is_anchor = False
        else:
            is_anchor = any(stripped.startswith(a) or a in stripped for a in anchor_labels)
        
        is_other_label = (not is_anchor) and any(stripped.startswith(l) or l in stripped for l in all_labels)

        if is_anchor:
            collecting = True
            remainder = line_u
            for a in anchor_labels:
                match = re.search(re.sub(r'[^A-Z]', r'[^A-Z]*', a), remainder)
                if match:
                    remainder = remainder[match.end():].strip()
                    break
            for lbl in all_labels:
                remainder = re.sub(re.sub(r'[^A-Z]', r'[^A-Z]*', lbl), ' ', remainder, flags=re.IGNORECASE).strip()
            remainder = re.sub(r'^[\s/\-:,\.]+', '', remainder).strip()
            remainder_words = [
                w for w in re.sub(r'[^A-Za-z\s]', ' ', remainder).split()
                if len(w) > 1 and w.upper() not in label_noise
            ]
            if remainder_words:
                region_parts.append(' '.join(remainder_words))
        elif collecting:
            if is_other_label:
                break
            name_words = [
                w for w in re.sub(r'[^A-Za-z\s]', ' ', line).split()
                if len(w) > 1 and w.upper() not in label_noise
            ]
            if name_words:
                region_parts.append(' '.join(name_words))

    return ' '.join(region_parts).strip()

last_r = extract_field_region(lines, ID_FIELD_ANCHORS["Philippine National ID (PhilSys)"]["last"], ALL_FIELD_LABELS)
first_r = extract_field_region(lines, ID_FIELD_ANCHORS["Philippine National ID (PhilSys)"]["first"], ALL_FIELD_LABELS)
mid_r = extract_field_region(lines, ID_FIELD_ANCHORS["Philippine National ID (PhilSys)"]["middle"], ALL_FIELD_LABELS)

print(f"EXTRACTED: last='{last_r}', first='{first_r}', mid='{mid_r}'")
