"""Install a verified OTA-only development image or reboot into the retained factory."""
import argparse
import binascii
import contextlib
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import tempfile
import time

import esptool
import serial
from serial.tools.list_ports import comports
from verify_backup import STOCK, verify

ROOT = Path.home() / "Library/Application Support/Keyberth/Recovery"
VERSION = "0.4.0-keyberth"
PREVIOUS_VERSION = "0.2.0-keyberth"
STOCK_VERSION = "0.2.18-ai-micro-agent"
IMAGE_HASH = "8f144506356a3e624c95005d5e29028ef58d8e48f4e10834cdec08e89651ca5f"
PREVIOUS_IMAGES = {668192:"f1e902efd1127eb15065f84f2ac9a231b93c9b39890347797df828bba005972d",667664:"b5a2c30e98171c12208d6feb9cdc2c4daca8539c6fedd8eb17a562a0cdcb5f3e",667520:"bdba3551fad7f3f3ef65293aceee70bc5ef45d2b04e9876d7cd421a6ec0d5b84",380960:"4e8dd9fd545e1499f6f6776f5475b033d9ef18f924ee1ebcbd10c80149a7f885",380912:"27e975ee8e75a846b5b2bbcc7401bbbcf7ede63c5d0bac92fda3dcfeedad2700"}
OLD_LENGTH = max(PREVIOUS_IMAGES)

OTA = 0x220000
SELECT = 0xf000

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def usb(pid, location=None):
    ports = [p for p in comports() if (p.vid,p.pid)==(0x303a,pid) and (location is None or p.location==location)]
    require(len(ports)==1, "같은 USB 위치에서 AI Micro 한 대를 확인할 수 없습니다.")
    return ports[0]

def query(port,command,prefix):
    with serial.Serial(port.device,115200,timeout=.25) as link:
        link.write(command+b"\n")
        deadline=time.monotonic()+3
        while time.monotonic()<deadline:
            line=link.readline()
            if line.startswith(prefix+b"\t"):
                return json.loads(line.split(b"\t",1)[1])
    raise RuntimeError("기기 상태 응답 시간 초과")

def status(port):
    return query(port,b"STATUS",b"CMSTATE")

def wait_for(check, seconds):
    end=time.monotonic()+seconds
    while True:
        try:
            return check()
        except (RuntimeError,OSError,ValueError):
            if time.monotonic()>=end:
                raise
            time.sleep(.3)

def run(action, image):
    port=usb(0x8360)
    initial=status(port)
    location=port.location
    mac=initial["base_mac"].lower()
    require(location and re.fullmatch(r"(?:[a-f0-9]{2}:){5}[a-f0-9]{2}",mac) and initial.get("hardware_revision")=="AI Micro","기기 식별 실패")
    def check(version, after_reboot=False):
        # A dock or a different physical port may change the USB location.
        # Only a read-only status query may follow it, and the MAC must match.
        try:
            app_port=usb(0x8360,location)
        except RuntimeError:
            if not after_reboot:
                raise
            app_port=usb(0x8360)
        result=status(app_port)
        require(result.get("base_mac","").lower()==mac and result.get("firmware")==version,"펌웨어 응답 대기")
        if version==STOCK_VERSION:
            require(result.get("running_partition")=="factory" and result.get("storage_layout_ok"),"정품 파티션 확인 실패")
        else:
            require(result.get("board_init")=="ESP_OK","보드 초기화 실패")
        return result
    if action in ("install","update") and initial.get("firmware")==VERSION:
        require(hashlib.sha256(image.read_bytes()).hexdigest()==IMAGE_HASH,"이미지 체크섬 불일치")
        check(VERSION)
        return "already-current"
    if action=="install":
        require(initial.get("firmware")==STOCK_VERSION,"기존 키버스 펌웨어가 설치되어 있습니다. 업데이트를 선택하세요.")
    if action=="reset":
        check(VERSION)
        with serial.Serial(port.device,115200,timeout=1) as link:
            link.write(b"KEYBERTH FACTORY_RESET CONFIRM\n")
            link.flush()
        time.sleep(2)
        def defaults():
            state=check(VERSION,after_reboot=True)
            require(state.get("ble_selected_channel")==1 and not state.get("ble_slot_bound")
                    and state.get("preferences_initialized") is False,"초기화 부팅 대기")
            saved=query(usb(0x8360),b'PREFS_GET\t{"id":925}',b"CMPREFS")
            expected=dict(sleepMinutes=15,volumePercent=50,buzzerEnabled=True,brightness=100,
                          standbyMinutes=5,standbyPowered=True,standbyBluetooth=False,styles=[""]*14)
            require(saved.get("ok") and all(saved.get(k)==v for k,v in expected.items()),"기본값 검증 실패")
        wait_for(defaults,25)
        return
    if action=="update":
        require(initial.get("firmware") in (PREVIOUS_VERSION,"0.3.0-keyberth",VERSION),"키버스 펌웨어에서 업데이트할 수 있습니다.")
        require(hashlib.sha256(image.read_bytes()).hexdigest()==IMAGE_HASH,"이미지 체크섬 불일치")
        check(initial["firmware"])
        with serial.Serial(port.device,115200,timeout=1) as link:
            link.write(b"KEYBERTH ROLLBACK\n");link.flush()
        wait_for(lambda:check(STOCK_VERSION,after_reboot=True),25)
        port=usb(0x8360)
        location=port.location
    if action=="rollback":
        if initial.get("firmware")!=STOCK_VERSION:
            require(initial.get("firmware") in (PREVIOUS_VERSION,"0.3.0-keyberth",VERSION),"지원하는 키버스-펌웨어만 롤백할 수 있습니다.")
            check(initial["firmware"])
            with serial.Serial(port.device,115200,timeout=1) as link:
                link.write(b"KEYBERTH ROLLBACK\n");link.flush()
        wait_for(lambda:check(STOCK_VERSION,after_reboot=True),25)
        return
    check(STOCK_VERSION)
    stock_settings=query(port,b'PREFS_GET\t{"id":921}',b"CMPREFS")
    require(stock_settings.get("ok") and stock_settings.get("id")==921,"정품 설정 읽기 실패")
    content=image.read_bytes()
    require(hashlib.sha256(content).hexdigest()==IMAGE_HASH,"시험 이미지 체크섬 불일치")
    work=Path(tempfile.mkdtemp(prefix="install-",dir=ROOT))
    def rom(*args, stub=True, reset=False):
        path=usb(0x1001,location).device
        output=io.StringIO()
        with contextlib.redirect_stdout(output):
            esptool.main(["--chip","esp32s3","--port",path,"--before","no_reset","--after","watchdog_reset" if reset else "no_reset",
                          *(["--baud","921600"] if stub else ["--no-stub"]),*map(str,args)])
        return output.getvalue()
    def read(start,length,file):
        rom("read_flash",hex(start),hex(length),file)
        data=file.read_bytes()
        require(len(data)==length,"플래시 읽기 길이 불일치")
        return data
    def reboot():
        require(mac in rom("read_mac",stub=False).lower(),"ROM 기기가 변경됐습니다.")
        rom("read_mac",stub=False,reset=True)
    try:
        with serial.Serial(port.device,1200,timeout=.5):
            time.sleep(.15)
    except serial.SerialException:
        pass
    wait_for(lambda:usb(0x1001,location),18)
    require(mac in rom("read_mac",stub=False).lower(),"ROM 기기 식별 실패")
    selector_touched=False
    original=work/"selection.bin"
    try:
        security=rom("get_security_info",stub=False)
        require("Secure Boot: Disabled" in security and "Flash Encryption: Disabled" in security and "Detected flash size: 16MB" in rom("flash_id",stub=False),"플래시 보안 상태 또는 용량 불일치")
        backup=None
        for identity in ROOT.glob("*/identity.json"):
            if json.loads(identity.read_text()).get("mac","").lower()!=mac:
                continue
            first,second=[identity.parent/f"flash-{n}.bin" for n in (1,2)]
            if first.is_file() and second.is_file():
                verify(first,second);backup=first;break
        if backup is None:
            print("동일 기기의 전체 백업 두 개를 생성하고 있습니다.",flush=True)
            first,second=[work/f"flash-{n}.bin" for n in (1,2)]
            for file in (first,second):
                read(0,0x1000000,file)
            verify(first,second)
            (work/"identity.json").write_text(json.dumps({"mac":mac}))
            backup=first
        for start,length,digest in STOCK:
            data=read(start,length,work/f"region-{start:x}.bin")
            require(hashlib.sha256(data).hexdigest()==digest,"정품 구성 요소 불일치")
        require(read(SELECT,8192,original)==bytes([255])*8192,"기존 OTA 선택 보존을 위해 중단했습니다.")
        reserved=read(0xc30000,65536,work/"settings-before.bin")
        require(reserved==bytes([255])*65536 or reserved[0xf000:].startswith(b"keyberth-settings-v1\0"),"설정 영역에 다른 데이터가 있습니다.")
        length=((max(len(content),OLD_LENGTH)+4095)//4096)*4096
        old=read(OTA,length,work/"slot-before.bin")
        pad=lambda n: bytes([255])*n
        current=content+pad(length-len(content))
        if old!=current:
            previous=any(hashlib.sha256(old[:n]).hexdigest()==digest and old[n:]==pad(length-n) for n,digest in PREVIOUS_IMAGES.items())
            require(previous or old==pad(length),"다른 OTA 이미지가 있어 중단했습니다.")
            slot_image=work/"verified-slot.bin"
            slot_image.write_bytes(current)
            rom("write_flash",hex(OTA),slot_image)
            require(read(OTA,length,work/"slot-after.bin")==current,"OTA 이미지 재읽기 실패")
        selector=bytearray(pad(4096))
        selector[:4]=struct.pack("<I",1)
        selector[24:28]=bytes(4)
        selector[28:32]=struct.pack("<I",binascii.crc32(selector[:4],0xffffffff))
        path=work/"trial-selection.bin";path.write_bytes(selector)
        selector_touched=True
        rom("write_flash",hex(SELECT),path)
        require(read(SELECT,8192,work/"selected.bin")==selector+pad(4096),"부팅 선택 검증 실패")
    except BaseException:
        if selector_touched:
            rom("write_flash",hex(SELECT),original)
            require(read(SELECT,8192,work/"restored.bin")==original.read_bytes(),"원본 부팅 선택 복원 실패")
        reboot()
        raise
    reboot()
    try:
        running=wait_for(lambda:check(VERSION,after_reboot=True),25)
    except (RuntimeError,OSError,ValueError) as error:
        raise RuntimeError("이미지는 검증됐지만 시험 부팅을 확인할 수 없습니다. Mac 본체에 직접 연결한 뒤 기기 버전을 확인하세요.") from error

    require(running.get("ble_init")=="ESP_OK","Bluetooth 초기화 실패 · 정품으로 롤백할 수 있습니다.")
    target=usb(0x8360)
    require(status(target).get("base_mac","").lower()==mac,"설정 대상 변경")
    keys=("sleepMinutes","volumePercent","standbyMinutes","standbyPowered","standbyBluetooth")
    seeded=not running.get("preferences_initialized")
    if seeded:
        fields={k:stock_settings[k] for k in keys}
        fields.update(version=1,id=922,revision=1,initialBuzzerEnabled=stock_settings["buzzerEnabled"])
        reply=query(target,b"PREFS_SET\t"+json.dumps(fields).encode(),b"CMPREFS")
        require(reply.get("ok") and reply.get("id")==922 and all(reply.get(k)==fields[k] for k in keys),"설정 이전 실패")

    saved=query(target,b'PREFS_GET\t{"id":923}',b"CMPREFS")
    require(saved.get("ok") and saved.get("id")==923 and saved.get("version")==1
            and saved.get("storageReady") is True,"설치 후 설정 저장소 응답 확인 실패")
    if seeded:
        require(all(saved.get(k)==stock_settings[k] for k in (*keys,"buzzerEnabled")),
                "설치 후 정품에서 이전한 설정 재확인 실패")

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("action",choices=["install","update","reset","rollback"])
    parser.add_argument("image",type=Path)
    args=parser.parse_args()
    os.umask(0o077)
    try:
        ROOT.mkdir(parents=True,exist_ok=True)
        with (ROOT/"maintenance.lock").open("a") as lock:
            try:
                fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RuntimeError("다른 펌웨어 작업이 진행 중입니다.") from error
            outcome=run(args.action,args.image)
    except Exception as error:
        parser.exit(1,f"펌웨어 오류 · {error}\n")
    print(outcome or (VERSION if args.action!="rollback" else STOCK_VERSION))
