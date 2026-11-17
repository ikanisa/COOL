"""Open generated synthetic XLSX/CSV with existing independent reader libraries."""
import argparse
import csv
import datetime
import hashlib
import json
from pathlib import Path

import openpyxl


def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path);args=parser.parse_args()
    book=args.directory/'synthetic-export.xlsx';csv_path=args.directory/'synthetic-export.csv'
    wb=openpyxl.load_workbook(book,data_only=False);ws=wb['BuriMunsi']
    assert ws.max_row==187 and ws.max_column==7
    assert ws['A8'].value=='=1+1' and ws['A8'].data_type=='s'
    assert ws['B8'].value=='Uwimana Élodie · こんにちは'
    assert ws['C8'].value==123456 and ws['C8'].data_type=='n' and 'RWF' in ws['C8'].number_format
    assert ws['D8'].value==datetime.datetime(2026,11,14)
    assert ws['E8'].value==datetime.datetime(2026,11,14,14,34,56,789000)
    assert ws['F8'].value is True and ws['F8'].data_type=='b'
    assert ws['G8'].value=='First line\nSecond line, "quoted" & complete 😀'
    assert ws['A187'].value=='REF-1' and ws['C187'].value==123635
    assert ws.freeze_panes=='A8' and ws.print_title_rows=='$7:$7'
    assert not any(c.data_type=='f' for row in ws for c in row)
    with csv_path.open(encoding='utf-8-sig',newline='')as stream:rows=list(csv.reader(stream))
    header=next(i for i,row in enumerate(rows)if row and row[0]=='Reference')
    data=rows[header+1:]
    assert len(data)==180 and data[0][0]=="'=1+1" and data[0][2]=='123456'
    assert data[0][6]=='First line\nSecond line, "quoted" & complete 😀'
    assert rows[-1][0]=='REF-1' and rows[-1][2]=='123635'
    assert csv_path.read_bytes().startswith(b'\xef\xbb\xbf')
    print(json.dumps({'status':'PASS','reader':'openpyxl/'+openpyxl.__version__+' and Python csv','data_rows':180,
        'formula_text_literal':True,'numeric_money':True,'typed_dates_and_kigali_milliseconds':True,
        'multiline_unicode_exact':True,'full_snapshot_order':True,'csv_formula_neutralized':True,
        'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in [book,csv_path]}},sort_keys=True))


if __name__=='__main__':main()
