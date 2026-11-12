import Foundation
import Darwin

/// Uso de memória: o do próprio app e o de cada painel (o shell e tudo o que ele abriu —
/// o Claude, o Codex, os servidores e ferramentas que eles rodam). É a mesma medida do Monitor
/// de Atividade ("Memória" = phys_footprint). Barato: uma passada pela tabela de processos.
enum Memoria {
  /// Memória do Orion Terminal em bytes.
  static func doApp() -> UInt64 {
    var info = task_vm_info_data_t()
    var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n) }
    }
    return r == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
  }

  private static func doProcesso(_ pid: pid_t) -> UInt64 {
    var ri = rusage_info_v4()
    let r = withUnsafeMutablePointer(to: &ri) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    return r == 0 ? ri.ri_phys_footprint : 0
  }

  /// Para cada raiz (pid do shell de um painel): bytes da árvore inteira e quantos processos ela tem.
  static func arvores(_ raizes: [pid_t]) -> [pid_t: (bytes: UInt64, processos: Int)] {
    guard !raizes.isEmpty else { return [:] }
    let total = proc_listallpids(nil, 0)
    guard total > 0 else { return [:] }
    var pids = [pid_t](repeating: 0, count: Int(total) + 64)
    let lidos = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard lidos > 0 else { return [:] }
    var filhos: [pid_t: [pid_t]] = [:]
    var bsd = proc_bsdinfo()
    let tam = Int32(MemoryLayout<proc_bsdinfo>.size)
    for p in pids.prefix(Int(lidos)) where p > 1 {
      if proc_pidinfo(p, PROC_PIDTBSDINFO, 0, &bsd, tam) == tam { filhos[pid_t(bsd.pbi_ppid), default: []].append(p) }
    }
    var saida: [pid_t: (bytes: UInt64, processos: Int)] = [:]
    for raiz in raizes {
      var soma: UInt64 = 0, n = 0
      var fila = [raiz]
      var vistos = Set<pid_t>()
      while let p = fila.popLast() {
        guard vistos.insert(p).inserted, vistos.count < 2000 else { continue }
        soma += doProcesso(p); n += 1
        fila.append(contentsOf: filhos[p] ?? [])
      }
      saida[raiz] = (soma, n)
    }
    return saida
  }

  /// Memória que o Mac ainda tem para dar (livre + inativa + purgável), em bytes — a mesma conta
  /// que o macOS faz antes de começar a comprimir e usar swap.
  static func disponivel() -> UInt64 {
    var stats = vm_statistics64_data_t()
    var n = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &n) }
    }
    guard r == KERN_SUCCESS else { return .max }
    let pagina = UInt64(vm_kernel_page_size)
    return (UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count)) * pagina
  }

  /// Nomes curtos (até 16 letras) dos processos abaixo de `raiz` — para saber se um agente
  /// parado ainda tem um comando rodando (o Bash do Claude roda como filho dele).
  static func descendentes(_ raiz: pid_t) -> [String] {
    let total = proc_listallpids(nil, 0)
    guard total > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(total) + 64)
    let lidos = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard lidos > 0 else { return [] }
    var filhos: [pid_t: [pid_t]] = [:]
    var nomes: [pid_t: String] = [:]
    var bsd = proc_bsdinfo()
    let tam = Int32(MemoryLayout<proc_bsdinfo>.size)
    for p in pids.prefix(Int(lidos)) where p > 1 {
      guard proc_pidinfo(p, PROC_PIDTBSDINFO, 0, &bsd, tam) == tam else { continue }
      filhos[pid_t(bsd.pbi_ppid), default: []].append(p)
      nomes[p] = withUnsafeBytes(of: bsd.pbi_comm) { b in String(decoding: b.prefix { $0 != 0 }, as: UTF8.self) }
    }
    var saida: [String] = []
    var fila = filhos[raiz] ?? []
    var vistos = Set<pid_t>()
    while let p = fila.popLast() {
      guard vistos.insert(p).inserted, vistos.count < 500 else { continue }
      saida.append(nomes[p] ?? "")
      fila.append(contentsOf: filhos[p] ?? [])
    }
    return saida
  }

  /// Devolve ao sistema as páginas que ficaram livres no heap (depois de fechar o quadro, os
  /// ajustes, um diálogo): sem isso a memória "usada" fica no pico mesmo com tudo fechado.
  static func aliviar() {
    DispatchQueue.global(qos: .utility).async { _ = malloc_zone_pressure_relief(nil, 0) }
  }

  /// "84 MB", "1,2 GB".
  static func texto(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    if mb < 1 { return "–" }
    if mb < 1000 { return "\(Int(mb.rounded())) MB" }
    return String(format: "%.1f GB", mb / 1024).replacingOccurrences(of: ".", with: ",")
  }
}
