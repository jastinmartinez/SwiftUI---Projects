import Fluent
import Vapor

func routes(_ app: Application) throws {
    
    try app.register(collection: UserController())
    
    try app.routes.grouped(User.authenticator()).group(User.guardMiddleware()) {secure in
        try secure.register(collection: DepartmentController())
        try secure.register(collection: ArticleController())
        try secure.register(collection: MeasureUnitController())
        try secure.register(collection: ProviderControlelr())
        try secure.register(collection: PurchaseOrderController())
    }
}
