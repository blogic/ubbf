#!/usr/bin/env python3

import argparse
import logging
import signal
import sys
from pathlib import Path

from flask import Flask, request, send_from_directory, abort
from waitress import serve

app = Flask(__name__)
storage_dir = None
log = logging.getLogger('http-server')


@app.route('/download/<path:filename>')
def download(filename):
    filepath = storage_dir / filename
    if not filepath.is_file():
        log.warning(f'download not found: {filename}')
        abort(404)
    log.info(f'download: {filename} ({filepath.stat().st_size} bytes)')
    return send_from_directory(storage_dir, filename)


@app.route('/upload/<path:filename>', methods=['POST', 'PUT'])
def upload(filename):
    filepath = storage_dir / filename
    filepath.parent.mkdir(parents=True, exist_ok=True)
    data = request.get_data()
    filepath.write_bytes(data)
    full_path = request.full_path.rstrip('?')
    encoding = request.headers.get('Content-Encoding', '')
    enc_info = f' [{encoding}]' if encoding else ''
    log.info(f'{request.method} {full_path} ({len(data)} bytes){enc_info}')
    return '', 204


def signal_handler(signum, frame):
    log.info('shutting down')
    sys.exit(0)


def main():
    global storage_dir

    parser = argparse.ArgumentParser(description='HTTP file transfer server')
    parser.add_argument('-p', '--port', type=int, default=8080,
                        help='listen port (default: 8080)')
    parser.add_argument('-b', '--bind', default='0.0.0.0',
                        help='bind address (default: 0.0.0.0)')
    parser.add_argument('-d', '--directory', type=Path, default=Path('./files'),
                        help='storage directory (default: ./files)')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='verbose logging')
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format='%(asctime)s %(levelname)s %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    storage_dir = args.directory.resolve()
    storage_dir.mkdir(parents=True, exist_ok=True)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    log.info(f'storage: {storage_dir}')
    log.info(f'listening on {args.bind}:{args.port}')

    serve(app, host=args.bind, port=args.port, _quiet=True)


if __name__ == '__main__':
    main()
