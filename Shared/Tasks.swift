import Foundation

// MARK: - «Справи»: tasks (to me, to the partner, to us; a list inside; repeating) and routines (steps with minutes, a streak)

struct TaskLine: Codable, Hashable { var t: String; var done: Bool }
struct TaskItem: Codable, Hashable, Identifiable {
    let id: String; var title: String; var note: String?; var items: [TaskLine]; var minutes: Int?; var important: Bool
    var due: String?; var `repeat`: String?
    /// me | partner | us — seen from the one who asks
    var assignee: String; var createdBy: String; var done: Bool; var doneBy: String?
}
struct TaskDay: Codable, Hashable { let date: String; var tasks: [TaskItem]; var done: Int; var total: Int }
/// The small widget of Головна: how many are done today and the next one.
struct DashTasks: Codable, Hashable { let done: Int; let total: Int; let next: TaskItem? }

struct RoutineStep: Codable, Hashable { var name: String; var minutes: Int }
struct RoutineDay: Codable, Hashable { let date: String; let on: Bool; let done: Bool }
struct Routine: Codable, Hashable, Identifiable {
    let id: String; let title: String; let icon: String; let days: [Int]; let steps: [RoutineStep]; let minutes: Int
    let owner: String; let doneToday: Bool; let today: Bool; let streak: Int; let week: [RoutineDay]
}

extension API {
    struct TaskNew: Encodable { let title: String; let assignee: String; let items: [String]; let minutes: Int?; let `repeat`: String?; let important: Bool }
    struct TaskPatch: Encodable { var title: String? = nil; var items: [TaskLine]? = nil; var done: Bool? = nil; var date: String? = nil }
    struct TaskResult: Decodable { let task: TaskItem }
    struct RoutineNew: Encodable { let title: String; let icon: String; let days: [Int]; let steps: [RoutineStep] }
    struct RoutineResult: Decodable { let routine: Routine }
    struct RoutinesResult: Decodable { let routines: [Routine] }

    func tasks(_ day: String) async throws -> TaskDay { try await get("/tasks?date=\(day)") }
    func addTask(_ t: TaskNew) async throws -> TaskItem { (try await send("POST", "/tasks", t) as TaskResult).task }
    func patchTask(_ id: String, _ p: TaskPatch) async throws -> TaskItem { (try await send("PATCH", "/tasks/\(id)", p) as TaskResult).task }
    func deleteTask(_ id: String) async throws { try await delete("/tasks/\(id)") }
    func routines() async throws -> [Routine] { (try await get("/routines") as RoutinesResult).routines }
    func addRoutine(_ r: RoutineNew) async throws -> Routine { (try await send("POST", "/routines", r) as RoutineResult).routine }
    func deleteRoutine(_ id: String) async throws { try await delete("/routines/\(id)") }
    func routineDone(_ id: String) async throws { let _: RoutineResult = try await send("POST", "/routines/\(id)/done", Empty()) }
}
