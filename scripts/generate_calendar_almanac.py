#!/usr/bin/env python3
"""Generate deterministic day-level almanacs; never needed by the running app.

python3 scripts/generate_calendar_almanac.py [--start-year 1901 --end-year 2099]
Source: https://github.com/OPN48/cnlunar
Pinned commit: 3f674fe0f458b480c79eaaf5464f43f4bc815a91 (MIT).
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'scripts/vendor/cnlunar'))
import cnlunar
from cnlunar.tools import sortCollation

COMMIT = '3f674fe0f458b480c79eaaf5464f43f4bc815a91'

def record(day):
    a = cnlunar.Lunar(day, godType='8char', year8Char='year', yeargod='duty')
    if a.lunarYear < 1901:
        return None  # Upstream arrays start in 1901; negative indices are not valid.
    officer, god, quality = a.get_today12DayOfficer()
    return dict(lunar=f'{a.lunarMonthCn}{a.lunarDayCn}',
                lunarYear=a.lunarYear, lunarMonth=a.lunarMonth, lunarDay=a.lunarDay,
                isLeap=a.isLunarLeapMonth, zodiac=a.chineseYearZodiac,
                pillars=f'{a.year8Char}年 {a.month8Char}月 {a.day8Char}日',
                good=sorted(a.goodThing, key=lambda x: (sortCollation(x), x)),
                bad=sorted(a.badThing, key=lambda x: (sortCollation(x), x)),
                goodGods=sorted(a.goodGodName), badGods=sorted(a.badGodName), level=a.todayLevelName,
                officer=officer, god=god, quality=quality,
                clash=a.chineseZodiacClash, peng=a.get_pengTaboo(),
                nayin=a.get_nayin(), solarTerm=a.todaySolarTerms)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--start-year', type=int, default=1901)
    parser.add_argument('--end-year', type=int, default=2099)
    parser.add_argument('--output-directory', type=Path, default=ROOT / 'Resources/Almanac')
    args = parser.parse_args()
    if not 1901 <= args.start_year <= args.end_year <= 2099:
        parser.error('Supported complete lunar years: 1901–2099')
    target = args.output_directory
    target.mkdir(parents=True, exist_ok=True)
    manifest = dict(schemaVersion=1, source='OPN48/cnlunar', commit=COMMIT,
                    parameters=dict(godType='8char', year8Char='year', yeargod='duty', hour=12), years={})
    first, last, total = None, None, 0
    for year in range(args.start_year, args.end_year + 1):
        records = {}
        day = dt.datetime(year, 1, 1, 12)
        while day.year == year:
            # Invalid first-year lunar dates are excluded before invoking source logic.
            if year == 1901 and day < dt.datetime(1901, 2, 19, 12):
                day += dt.timedelta(days=1)
                continue
            value = record(day)  # Fail loudly; never silently ship missing dates.
            if value is not None:
                key = day.strftime('%Y-%m-%d')
                records[key] = value
                first = first or key
                last = key
            day += dt.timedelta(days=1)
        compressor = zlib.compressobj(level=9, wbits=-15)  # Foundation .zlib uses raw DEFLATE.
        raw = json.dumps(records, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
        payload = compressor.compress(raw) + compressor.flush()
        (target / f'{year}.json.deflate').write_bytes(payload)
        manifest['years'][str(year)] = dict(count=len(records), sha256=hashlib.sha256(payload).hexdigest())
        total += len(records)
        print(f'{year}: {len(records)} days, {len(payload)} bytes', flush=True)
    manifest.update(firstDate=first, lastDate=last, count=total)
    (target / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')

if __name__ == '__main__':
    main()
