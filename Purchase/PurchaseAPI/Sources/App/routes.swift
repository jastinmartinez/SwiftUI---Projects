import Fluent
import Vapor

func routes(_ app: Application) throws {
    
    try app.register(collection: DepartmentController())
    try app.register(collection: ArticleController())
    try app.register(collection: MeasureUnitController())
    try app.register(collection: ProviderControlelr())
    try app.register(collection: PurchaseOrderController())
}
