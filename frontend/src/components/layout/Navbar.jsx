import React from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../../hooks/useAuth';
import { Calendar, User, UserCog, LogOut, Home, Search } from 'lucide-react';

const Navbar = () => {
    const { user, admin, isAuthenticated, isAdminAuthenticated, userLogout, adminLogout } = useAuth();
    const navigate = useNavigate();

    const handleUserLogout = async () => {
        await userLogout();
        navigate('/');
    };

    const handleAdminLogout = () => {
        adminLogout();
        navigate('/');
    };

    return (
        <nav className="bg-white shadow-lg border-b">
            <div className="container mx-auto px-4">
                <div className="flex justify-between items-center h-16">
                    {/* Logo */}
                    <Link to="/" className="flex items-center space-x-2 text-xl font-bold text-[#e21833]">
                        <Calendar className="h-6 w-6" />
                        <span>CampusEventManager</span>
                    </Link>

                    {/* Navigation Links */}
                    <div className="hidden md:flex items-center space-x-6">
                        <Link to="/" className="flex items-center space-x-1 text-gray-600 hover:text-[#e21833]">
                            <Home className="h-4 w-4" />
                            <span>Home</span>
                        </Link>
                        <Link to="/events" className="flex items-center space-x-1 text-gray-600 hover:text-[#e21833]">
                            <Search className="h-4 w-4" />
                            <span>Events</span>
                        </Link>
                    </div>

                    {/* User/Admin Actions */}
                    <div className="flex items-center space-x-4">
                        {isAuthenticated && user ? (
                            // User is logged in
                            <div className="flex items-center space-x-4">
                                <Link to="/dashboard" className="flex items-center space-x-1 text-gray-600 hover:text-[#e21833]">
                                    <User className="h-4 w-4" />
                                    <span>Dashboard</span>
                                </Link>
                                <div className="flex items-center space-x-2">
                                    <span className="text-sm text-gray-600">Hi, {user.name}</span>
                                    <button
                                        onClick={handleUserLogout}
                                        className="flex items-center space-x-1 text-gray-600 hover:text-red-600"
                                    >
                                        <LogOut className="h-4 w-4" />
                                        <span>Logout</span>
                                    </button>
                                </div>
                            </div>
                        ) : isAdminAuthenticated && admin ? (
                            // Admin is logged in
                            <div className="flex items-center space-x-4">
                                <Link to="/admin/dashboard" className="flex items-center space-x-1 text-gray-600 hover:text-purple-500">
                                    <UserCog className="h-4 w-4" />
                                    <span>Admin</span>
                                </Link>
                                <div className="flex items-center space-x-2">
                                    <span className="text-sm text-gray-600">Admin: {admin.name}</span>
                                    <button
                                        onClick={handleAdminLogout}
                                        className="flex items-center space-x-1 text-gray-600 hover:text-red-600"
                                    >
                                        <LogOut className="h-4 w-4" />
                                        <span>Logout</span>
                                    </button>
                                </div>
                            </div>
                        ) : (
                            // Not logged in
                            <div className="flex items-center space-x-4">
                                <Link to="/login" className="text-gray-600 hover:text-[#e21833]">
                                    Login
                                </Link>
                                <Link to="/register" className="bg-[#e21833] text-white px-4 py-2 rounded-md hover:bg-black">
                                    Register
                                </Link>
                                <div className="border-l border-gray-300 h-6"></div>
                                <Link to="/admin/login" className="text-sm text-gray-500 hover:text-purple-500">
                                    Admin
                                </Link>
                            </div>
                        )}
                    </div>
                </div>

                {/* Mobile menu */}
                <div className="md:hidden py-4 border-t">
                    <div className="flex flex-col space-y-2">
                        <Link to="/" className="text-gray-600 hover:text-[#e21833] py-2">Home</Link>
                        <Link to="/events" className="text-gray-600 hover:text-[#e21833] py-2">Events</Link>
                        {isAuthenticated && (
                            <Link to="/dashboard" className="text-gray-600 hover:text-[#e21833] py-2">Dashboard</Link>
                        )}
                        {isAdminAuthenticated && (
                            <Link to="/admin/dashboard" className="text-gray-600 hover:text-[#e21833] py-2">Admin Dashboard</Link>
                        )}
                    </div>
                </div>
            </div>
        </nav>
    );
};

export default Navbar;
