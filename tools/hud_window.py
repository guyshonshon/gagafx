#!/usr/bin/env python3
import json
import os
import sys
import time
import tkinter as tk
from tkinter import ttk

"""
Simple always-on-top HUD window that watches MQL5/Files/hud_status.json
and displays the latest status exported by the EA.

Usage:
  python tools/hud_window.py [path_to_MQL5_Files]

Notes:
  - Set the EA input ExportPayload or leave it; this script relies on hud_status.json
    which the EA writes each bar.
  - Toggle the "Always on top" checkbox to pin the HUD.
"""

def find_files_dir(arg_path: str | None) -> str:
    if arg_path:
        return arg_path
    # Default to current working directory's MQL5/Files if exists
    cand = os.path.join(os.getcwd(), 'MQL5', 'Files')
    return cand if os.path.isdir(cand) else os.getcwd()


class HUDWindow:
    def __init__(self, root: tk.Tk, files_dir: str):
        self.root = root
        self.files_dir = files_dir
        self.path = os.path.join(files_dir, 'hud_status.json')
        self.root.title('GagaFX HUD')
        self.root.attributes('-topmost', True)
        self.root.resizable(False, False)
        self.build_ui()
        self.last_mtime = 0.0
        self.poll()

    def build_ui(self):
        frm = ttk.Frame(self.root, padding=8)
        frm.grid(row=0, column=0, sticky='nsew')
        self.lbl_head = ttk.Label(frm, text='—', font=('Segoe UI', 10, 'bold'))
        self.lbl_p = ttk.Label(frm, text='—', font=('Consolas', 10))
        self.lbl_next = ttk.Label(frm, text='—', font=('Consolas', 10))
        self.lbl_est = ttk.Label(frm, text='—', font=('Consolas', 10))
        self.var_top = tk.BooleanVar(value=True)
        self.chk_top = ttk.Checkbutton(frm, text='Always on top', variable=self.var_top, command=self.on_top_toggle)
        self.lbl_head.grid(row=0, column=0, sticky='w')
        self.lbl_p.grid(row=1, column=0, sticky='w')
        self.lbl_next.grid(row=2, column=0, sticky='w')
        self.lbl_est.grid(row=3, column=0, sticky='w')
        self.chk_top.grid(row=4, column=0, sticky='w', pady=(6,0))

    def on_top_toggle(self):
        self.root.attributes('-topmost', bool(self.var_top.get()))

    def poll(self):
        try:
            if os.path.isfile(self.path):
                mtime = os.path.getmtime(self.path)
                if mtime != self.last_mtime:
                    self.last_mtime = mtime
                    with open(self.path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    sym = data.get('symbol', '?')
                    tf  = data.get('timeframe', '?')
                    t   = data.get('time', '')
                    p   = data.get('pred', {})
                    nx  = data.get('next', {})
                    self.lbl_head.config(text=f"{sym}  TF:{tf}  {t}")
                    self.lbl_p.config(text=f"Pred(+1,+2,+3): {p.get('p1',0):.2f}, {p.get('p2',0):.2f}, {p.get('p3',0):.2f}")
                    self.lbl_next.config(text=f"Next: {nx.get('side','FLAT')} {nx.get('lots',0):.2f} @ {nx.get('entry',0)}  Lev:{nx.get('lev',0):.2f}")
                    self.lbl_est.config(text=f"Est Px: {nx.get('est_px','-')}")
        except Exception as e:
            # Avoid crashing on partial writes
            pass
        finally:
            self.root.after(500, self.poll)


def main():
    files_dir = find_files_dir(sys.argv[1] if len(sys.argv) > 1 else None)
    root = tk.Tk()
    HUDWindow(root, files_dir)
    root.mainloop()


if __name__ == '__main__':
    main()

