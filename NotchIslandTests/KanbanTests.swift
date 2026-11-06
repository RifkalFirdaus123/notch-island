import Foundation
import Testing
@testable import NotchIsland

@MainActor
struct KanbanTests {
    @Test func decodesBoardInColumnOrder() throws {
        let json = """
        {"data":{"columns":{
            "review":[{"id":3,"title":"C","status":"review","product":null,"due_date":"2026-11-01T10:00:00.000000Z",
                       "sla_summary":{"color":"merah","percentage":120}}],
            "todo":[{"id":1,"title":"A","status":"todo","due_date":null}],
            "completed":[{"id":9,"title":"Done","status":"completed"}],
            "in_progress":[{"id":2,"title":"B","status":"in_progress","product":"Qaraa","due_date":"2026-12-01 09:00:00"}]
        },"summary":{"hijau":0,"kuning":0,"merah":1,"total_active":3}}}
        """
        let tasks = try KanbanClient.decodeBoard(Data(json.utf8))
        #expect(tasks.map(\.id) == [1, 2, 3, 9])
        #expect(tasks.filter { !$0.status.isFinished }.map(\.id) == [1, 2, 3])
        #expect(tasks[1].product == "Qaraa")
        #expect(tasks[1].dueDate != nil)
        #expect(tasks[2].slaColor == "merah")
        #expect(tasks[2].dueDate != nil)
    }

    @Test func emptyColumnsArrayDecodes() throws {
        let tasks = try KanbanClient.decodeBoard(Data(#"{"data":{"columns":[]}}"#.utf8))
        #expect(tasks.isEmpty)
    }
}
