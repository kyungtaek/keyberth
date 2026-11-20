import Darwin
import Foundation
import Security

/// A persistent local connection keeps terminal key repeat independent of CLI
/// startup time. Each space is acknowledged before the next repeat is sent.
final class CmuxRepeatConnection {
    private let socketFD: Int32
    init(path: String) throws {
        var address = sockaddr_un()
        let pathBytes = Array(path.utf8CString)
        guard path.hasPrefix("/"), pathBytes.count <= MemoryLayout.size(ofValue:address.sun_path) else {
            throw CompanionError("cmux 소켓 경로를 확인하세요.")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) { $0.copyBytes(from:pathBytes.map { UInt8(bitPattern:$0) }) }
        socketFD = socket(AF_UNIX,SOCK_STREAM,0)
        guard socketFD >= 0 else { throw CompanionError("cmux 소켓을 열 수 없습니다.") }
        let connected = withUnsafePointer(to:&address) { p in
            p.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(socketFD,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw CompanionError("cmux 소켓에 연결할 수 없습니다.") }
        var one:Int32=1, timeout=timeval(tv_sec:1,tv_usec:0)
        setsockopt(socketFD,SOL_SOCKET,SO_NOSIGPIPE,&one,socklen_t(MemoryLayout.size(ofValue:one)))
        for option in [SO_RCVTIMEO,SO_SNDTIMEO] {
            setsockopt(socketFD,SOL_SOCKET,option,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
        }

        let ping=try response(["id":"ping","method":"system.ping","params":[:]])
        if ping["ok"] as? Bool == true { return }
        guard (ping["error"] as? [String:Any])?["code"] as? String == "auth_required" else {
            throw CompanionError("cmux 소켓 접근 권한을 확인하세요.")
        }
        // Verify the peer against the installed cmux signature before sending
        // a saved credential, including when a custom socket path is in use.
        var pid:pid_t=0, length=socklen_t(MemoryLayout<pid_t>.size)
        var peer:SecCode?, installed:SecStaticCode?, requirement:SecRequirement?
        let cmux=URL(fileURLWithPath:"/Applications/cmux.app") as CFURL
        guard getsockopt(socketFD,SOL_LOCAL,LOCAL_PEERPID,&pid,&length)==0,
              SecCodeCopyGuestWithAttributes(nil,[kSecGuestAttributePid:pid] as CFDictionary,[],&peer)==errSecSuccess,let peer,
              SecStaticCodeCreateWithPath(cmux,[],&installed)==errSecSuccess,let installed,
              SecCodeCopyDesignatedRequirement(installed,[],&requirement)==errSecSuccess,let requirement,
              SecCodeCheckValidity(peer,[],requirement)==errSecSuccess else { throw CompanionError("cmux 소켓 소유자를 확인할 수 없습니다.") }
        let env=ProcessInfo.processInfo.environment
        let file=env["CMUX_SOCKET_PASSWORD_FILE"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/cmux/socket-control-password").path
        let password=env["CMUX_SOCKET_PASSWORD"] ?? (try? String(contentsOfFile:file,encoding:.utf8))?.trimmingCharacters(in:.newlines)
        guard let password,!password.isEmpty,!password.contains(where: { $0.isNewline }),
              try exchange(Data(("auth "+password+"\n").utf8)).starts(with:Data("OK".utf8)) else {
            throw CompanionError("cmux 소켓 비밀번호를 확인하세요.")
        }
    }
    deinit { close(socketFD) }
    private func exchange(_ data:Data) throws -> Data {
        try data.withUnsafeBytes { bytes in
            var sent=0
            while sent < bytes.count {
                let n=write(socketFD,bytes.baseAddress!.advanced(by:sent),bytes.count-sent)
                guard n>0 else { throw CompanionError("cmux 키 입력 전송 실패") }
                sent+=n
            }
        }
        var result=Data(), buffer=[UInt8](repeating:0,count:1024)
        while result.count<65_536 {
            let n=read(socketFD,&buffer,buffer.count)
            guard n>0 else { throw CompanionError("cmux 키 입력 응답 시간 초과") }
            result.append(contentsOf:buffer.prefix(n))
            if result.last==10 {return result}
        }
        throw CompanionError("cmux 응답 크기 초과")
    }
    private func response(_ message:[String:Any]) throws -> [String:Any] {
        var data=try JSONSerialization.data(withJSONObject:message)
        data.append(10)
        return try JSONSerialization.jsonObject(with:exchange(data)) as? [String:Any] ?? [:]
    }
    func space(_ target:[String:String]) throws {
        let reply=try response(["id":"space","method":"surface.send_text","params":target])
        guard reply["ok"] as? Bool == true else { throw CompanionError("cmux 터미널이 공백 입력을 받지 못했습니다.") }
    }
}
