#!/usr/bin/env python3
"""Presentation sheet for the mascot round (concepts-mascots). Run: python3 tools/make_mascot_icons_sheet.py"""
import pathlib
from make_icon_concepts_sheet import build
ROOT = pathlib.Path(__file__).resolve().parents[3] / "design" / "ember-sky" / "icon" / "concepts-mascots"
CONCEPTS = [
    ("11-hero-cat",  "1 · Qahramon mushuk", "Krem mushuk, ember peshonabog', ko'tarilgan panja. Sizga yoqqan 'Hero Cat' — lekin uyg'oq va qat'iy."),
    ("12-focus-fox", "2 · Fokus tulki",     "Ember tulki ilova palitrasiga tabiiy tushadi. Krem peshonabog', qisilgan ko'z. Eng kuchli xarakter."),
    ("13-owl",       "3 · Boyo'g'li",       "Tunda uxlamaydigan qush: katta oltin ko'z, qovoq-qosh. 'Men ko'rib turibman' kayfiyati."),
    ("14-penguin",   "4 · Pingvin",         "Qorong'i tana + oltin nur, ember sharf. Sizga yoqqan pingvin — endi uxlamaydi, qoshi tushgan."),
    ("15-tiger",     "5 · Yo'lbars",        "Eng 'no snooze': ember yuz, siyoh chiziqlar, o'tkir nigoh. Kuch va intizom."),
]
if __name__ == "__main__":
    build(CONCEPTS, ROOT / "png", "Dawnwick · maskot icon konseptlari (2‑raund)",
          "5 ta hayvon maskot · vektor, qo'lda qurilgan yoritish · 1024 px · 2026‑09‑12", ROOT / "sheet.png")
